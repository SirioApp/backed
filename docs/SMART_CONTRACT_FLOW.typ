#set page(margin: (x: 2.4cm, y: 2.6cm))
#set text(size: 10.5pt)
#set par(justify: true, leading: 0.66em)
#let card(title, body) = table(
  columns: (22%, 78%),
  inset: 8pt,
  stroke: 0.4pt + luma(180),
  align: (left, left),
  [*#title*],
  [#body],
)

#let field(label, value) = table(
  columns: (24%, 76%),
  inset: (x: 0pt, y: 2pt),
  stroke: none,
  align: (left, left),
  [*#label*],
  [#value],
)

= Backed Agent Raise Lifecycle

== Purpose

This document describes the implemented lifecycle of a Backed agent raise from project origination to post-raise treasury operation. It is intentionally grounded in the current contracts and tests rather than in a product abstraction.

The system is organized around one atomic creation call that deploys a project envelope composed of a Safe treasury, a `Sale`, and an `AgentExecutor`. Fundraising, capitalization, and treasury operation are then handled as distinct stages with different authority boundaries.

== System State Machine

#card([Identity exists], [
  #field([On-chain condition], [IDENTITY_REGISTRY.ownerOf(agentId) resolves])
  #parbreak()
  #field([Primary contract], [IERC8004IdentityRegistry])
  #parbreak()
  #field([Operational meaning], [Precondition for project creation. The repo only depends on identity ownership reads; registration itself is external to the in-repo interface.])
])

#card([Project created], [
  #field([On-chain condition], [Project stored, projectApproved == false, operationalStatus == STATUS_RAISING])
  #parbreak()
  #field([Primary contract], [AgentRaiseFactory])
  #parbreak()
  #field([Operational meaning], [The project envelope exists but Sale.commit(...) is still blocked by NotApproved().])
])

#card([Approved pre-launch], [
  #field([On-chain condition], [projectApproved == true, block.timestamp < startTime])
  #parbreak()
  #field([Primary contract], [AgentRaiseFactory + Sale])
  #parbreak()
  #field([Operational meaning], [The raise is authorized but not yet active because the sale window has not opened.])
])

#card([Active sale], [
  #field([On-chain condition], [projectApproved == true, startTime <= now < endTime, finalized == false])
  #parbreak()
  #field([Primary contract], [Sale])
  #parbreak()
  #field([Operational meaning], [Investors can commit collateral if token transfer behavior is valid.])
])

#card([Finalized failed], [
  #field([On-chain condition], [finalized == true, failed == true])
  #parbreak()
  #field([Primary contract], [Sale])
  #parbreak()
  #field([Operational meaning], [The raise either had no commitments, remained below MIN_RAISE, or was force-failed through emergencyRefund().])
])

#card([Finalized success], [
  #field([On-chain condition], [finalized == true, failed == false, token() != 0x0])
  #parbreak()
  #field([Primary contract], [Sale + AgentVaultToken])
  #parbreak()
  #field([Operational meaning], [Accepted collateral has been bootstrapped into a fixed-supply vault and investors can claim shares plus any overflow refund.])
])

#card([Treasury operating], [
  #field([On-chain condition], [Successful finalization plus configured execution policy])
  #parbreak()
  #field([Primary contract], [AgentExecutor + AgentVaultToken])
  #parbreak()
  #field([Operational meaning], [The treasury can be used through the Safe module path under the executor policy.])
])

One nuance is operationally important: revoking project approval stops new commitments, but it does not unwind prior commitments and does not block later `finalize()` once the sale window has ended.

== Contract Surfaces

#card([IERC8004IdentityRegistry], [
  #field([Role in the implemented flow], [Read-only dependency used by the factory to verify who owns agentId at creation time. The in-repo interface does not expose a registration write method.])
])

#card([AgentRaiseFactory], [
  #field([Role in the implemented flow], [Origination and governance entry point. It validates creation parameters, deploys the project envelope, stores project metadata, exposes aggregate read methods, and gates commitments through explicit approval.])
])

#card([Sale], [
  #field([Role in the implemented flow], [Time-bounded fundraising contract. It accepts commitments, resolves finalization, deploys the vault on success, and exposes investor settlement paths through claim() or refund().])
])

#card([AgentVaultToken], [
  #field([Role in the implemented flow], [Fixed-supply ERC-4626 vault created only on successful finalization. It receives accepted sale proceeds during bootstrap and later receives profits from the treasury through distributeProfits(uint256).])
])

#card([AgentExecutor], [
  #field([Role in the implemented flow], [Per-project Safe module controlled by the designated operator wallet. It forwards only Call operations and enforces target, selector, and approval-spender policy when allowlist enforcement is active.])
])

#card([ContractAllowlist], [
  #field([Role in the implemented flow], [Global registry of call targets that executor instances may use when allowlist enforcement is on. Selector policy is not stored here; it is stored per executor.])
])

== Role Model

#card([Project creator], [
  #field([Authority source], [IDENTITY_REGISTRY.ownerOf(agentId) == msg.sender at creation])
  #parbreak()
  #field([Typical methods], [createAgentRaise(...), updateProjectOperationalStatus(...)])
  #parbreak()
  #field([Practical significance], [The identity holder that originates the project. After creation the factory stores this address as project.agent; later status updates use the stored address, not a fresh ownerOf(agentId) check.])
])

#card([Agent operator], [
  #field([Authority source], [agentAddress supplied to createAgentRaise(...)])
  #parbreak()
  #field([Typical methods], [AgentExecutor.execute(...)])
  #parbreak()
  #field([Practical significance], [The only address allowed to trigger treasury-originated module calls through the executor. This role is distinct from the project creator.])
])

#card([Factory admin], [
  #field([Authority source], [AgentRaiseFactory.ADMIN])
  #parbreak()
  #field([Typical methods], [approveProject(...), revokeProject(...), setGlobalConfig(...), setAllowedCollateral(...)])
  #parbreak()
  #field([Practical significance], [Controls fundraising policy and global platform configuration. It is also the value returned by SUPER_ADMIN() to Sale.])
])

#card([Executor admin], [
  #field([Authority source], [AgentExecutor.ADMIN])
  #parbreak()
  #field([Typical methods], [setAllowlistEnforced(...), setSelectorAllowed(...), setSelectorsAllowed(...)])
  #parbreak()
  #field([Practical significance], [Controls per-executor policy. In the factory deployment path this is set to the factory admin address, but it is conceptually a distinct authority surface.])
])

#card([Allowlist admin], [
  #field([Authority source], [ContractAllowlist.admin])
  #parbreak()
  #field([Typical methods], [addContract(...), removeContract(...), batch variants])
  #parbreak()
  #field([Practical significance], [Controls the global target registry shared by executors. This may match the factory admin in deployment, but it is stored on a different contract and can diverge.])
])

#card([Investor], [
  #field([Authority source], [External participant])
  #parbreak()
  #field([Typical methods], [commit(...), claim(), refund(), getClaimable(...), getRefundable(...)])
  #parbreak()
  #field([Practical significance], [Provides collateral during the active sale window and later settles into shares or refunds depending on the sale outcome.])
])

#card([Any caller], [
  #field([Authority source], [No privileged role required])
  #parbreak()
  #field([Typical methods], [finalize()])
  #parbreak()
  #field([Practical significance], [Closes a finished sale after endTime. The protocol does not depend on a trusted closer.])
])

== Lifecycle

=== 1. Identity-gated origination

The factory does not treat arbitrary wallet possession as sufficient for project creation. The hard requirement is that the caller owns the supplied identity token:

```solidity
IDENTITY_REGISTRY.ownerOf(agentId) == msg.sender
```

The repository only depends on this ownership read. Registration itself is deployment-specific: tests use `MockIdentityRegistry.register(...)`, while the in-repo `IERC8004IdentityRegistry` interface exposes only read methods such as `ownerOf(...)`, `tokenURI(...)`, and `getAgentWallet(...)`.

=== 2. Atomic project creation

Project origination is performed through:

```solidity
function createAgentRaise(
    uint256 agentId,
    string calldata name,
    string calldata description,
    string calldata categories,
    address agentAddress,
    address collateral,
    uint256 duration,
    uint256 launchTime,
    string calldata tokenName,
    string calldata tokenSymbol
) external returns (uint256 projectId)
```

The factory validates at least the following:

- the caller owns `agentId`;
- `name` is non-empty;
- `duration` and `launchTime` are non-zero;
- `agentAddress` is non-zero;
- `collateral` is enabled and exposes supported decimals;
- `duration` fits inside `globalConfig.minDuration` and `globalConfig.maxDuration`;
- `launchTime` is not in the past and the launch delay fits inside configured bounds;
- scaled `minRaise` and `maxRaise` remain coherent after adapting from 18 decimals to collateral decimals.

If validation passes, the factory performs a single birth sequence:

1. create a one-owner Safe treasury for the project creator;
2. deploy a project-specific `Sale`;
3. deploy a project-specific `AgentExecutor`;
4. enable the executor as a Safe module;
5. remove the factory from the Safe module list;
6. store the `AgentProject` record;
7. emit `AgentRaiseCreated(...)`.

The resulting project exposes three canonical addresses that downstream tooling should persist immediately:

- `treasury`
- `sale`
- `agentExecutor`

=== 3. Immediate post-creation state

Creation does not make the raise investable. Right after origination the factory stores:

- `operationalStatus = STATUS_RAISING`
- `statusNote = "Raise created"`
- `projectApproved = false`

The sale window is already scheduled through `startTime` and `endTime`, but `Sale.commit(...)` remains blocked until explicit approval.

=== 4. Approval and commitment intake

The commitment gate is explicit:

```solidity
if (!FACTORY.isProjectApproved(PROJECT_ID)) revert NotApproved();
if (block.timestamp < startTime || block.timestamp >= endTime) revert NotActive();
```

Once approved, investors can call:

```solidity
function commit(uint256 amount) external
```

The commitment path has several implementation details that matter operationally:

- collateral is pulled with `safeTransferFrom`;
- accounting is based on the actual balance delta;
- if the received amount is zero, the call reverts with `InvalidCollateralTransfer()`;
- if the received amount differs from the requested amount, the call reverts with `InvalidCollateralBehavior()`;
- first participation increments `participantCount`;
- aggregate intake accumulates in `totalCommitted`.

This means fee-on-transfer or otherwise non-standard collateral behavior is rejected at the contract level rather than left as an integration caveat.

=== 5. Finalization and sale resolution

After `endTime`, any caller may resolve the sale:

```solidity
function finalize() external
```

The implemented logic produces three terminal outcomes:

1. `totalCommitted == 0`
   The sale finalizes as failed with no vault deployment.

2. `totalCommitted > 0` but `acceptedAmount < MIN_RAISE`
   The sale finalizes as failed and investors later recover collateral through `refund()`.

3. `acceptedAmount >= MIN_RAISE`
   The sale finalizes successfully.

The accepted amount is always:

```solidity
acceptedAmount = totalCommitted > MAX_RAISE ? MAX_RAISE : totalCommitted;
```

In the successful path the sale then:

1. deploys `AgentVaultToken`;
2. approves the vault to pull `acceptedAmount`;
3. bootstraps the vault with the accepted collateral;
4. receives the entire fixed share supply on the sale contract;
5. calls `completeSale()`;
6. emits `Finalized(vault, acceptedAmount, sharesMinted)`.

The overflow above `MAX_RAISE` remains on the sale contract for later pro-rata refunds during investor claims.

=== 6. Investor settlement

After finalization, investor resolution follows one of two mutually exclusive paths.

If the raise succeeded, investors call:

```solidity
function claim() external
```

Claiming transfers:

- vault shares corresponding to the caller's accepted contribution;
- a collateral refund for any unaccepted overflow.

The claim path contains one detail that should be reflected in any off-chain preview: the final claimer receives the residual accepted amount and residual share balance so that rounding dust does not remain trapped in the sale.

If the raise failed, investors call:

```solidity
function refund() external
```

This returns the full committed collateral.

There is also an emergency failure path:

```solidity
function emergencyRefund() external
```

This function is admin-only through `FACTORY.SUPER_ADMIN()` and marks the sale as finalized and failed before standard finalization, enabling investors to recover funds through `refund()`.

=== 7. Post-raise treasury operation

Successful finalization does not end the system lifecycle. It begins the treasury operation phase.

The treasury is a Safe, but the intended operational surface is the project-specific module:

```solidity
function execute(address target, uint256 value, bytes calldata data)
    external
    returns (bytes memory result)
```

This call path is reserved to the immutable `AGENT` address configured at creation time. In the default deployment model it is the operator wallet, not the project creator and not the admin.

== Treasury Execution Policy

The executor does not expose unrestricted Safe access. Its policy model is layered.

#card([Operator-only entry], [
  #field([Effect], [Only AGENT may call execute(...). Any other caller reverts with Unauthorized().])
])

#card([Hard-blocked targets], [
  #field([Effect], [TREASURY, address(this), and address(ALLOWLIST) can never be targeted, even when allowlist enforcement is disabled.])
])

#card([Call-only forwarding], [
  #field([Effect], [Execution always uses ISafe.Operation.Call. The executor never forwards DelegateCall.])
])

#card([Global target allowlist], [
  #field([Effect], [When allowlistEnforced == true, the target must be allowed in ContractAllowlist. This registry is shared across executors.])
])

#card([Per-executor selector policy], [
  #field([Effect], [When allowlistEnforced == true, the selector must be enabled in the specific executor instance through setSelectorAllowed(...) or setSelectorsAllowed(...).])
])

#card([Approval recipient checks], [
  #field([Effect], [When the selector is approve, increaseAllowance, decreaseAllowance, or setApprovalForAll, the decoded spender or operator must also be allowlisted and must not be the treasury, executor, or allowlist contract.])
])

#card([Break-glass mode], [
  #field([Effect], [If executor admin calls setAllowlistEnforced(false), target allowlist checks, selector checks, and approval-spender checks are all bypassed. Only the hard-blocked targets remain forbidden.])
])

This split matters for integrations. Target authorization is global through `ContractAllowlist`, while selector authorization is local to each project executor.

== Economic Path After Success

The success path converts accepted collateral into fixed-supply ownership rather than into continuously mintable shares.

`AgentVaultToken` bootstraps exactly once and mints the fixed supply to the sale contract. After that:

- `deposit(...)` is disabled;
- `mint(...)` is disabled;
- investor upside comes from asset accretion inside the vault, not from additional share issuance.

The canonical treasury profit path is:

1. allowlist admin authorizes the collateral token and vault contract if enforcement is on;
2. executor admin enables the required selectors, usually `approve(address,uint256)` on the collateral token and `distributeProfits(uint256)` on the vault;
3. the operator calls `AgentExecutor.execute(...)` to approve the vault as spender;
4. the operator calls `AgentExecutor.execute(...)` again to invoke `distributeProfits(...)`;
5. the vault pulls `grossAmount` from the treasury, routes the platform fee to `PLATFORM_FEE_RECIPIENT`, and retains the net amount;
6. redemption value rises for all fixed-supply shareholders.

The platform fee is therefore applied during profit distribution, not during initial bootstrap.

== Trust Boundaries and Failure Surfaces

#card([Identity and origination], [
  #field([Representative errors], [NotAgentOwner(), InvalidParams(), InvalidAddress()])
  #parbreak()
  #field([Meaning], [Project creation is denied unless the caller owns the identity token and supplies structurally valid parameters.])
])

#card([Collateral policy], [
  #field([Representative errors], [UnsupportedCollateral(), UnsupportedTokenDecimals(), InvalidConfig()])
  #parbreak()
  #field([Meaning], [Creation and commitment depend on collateral and scaled raise bounds remaining valid for the selected token decimals.])
])

#card([Raise scheduling], [
  #field([Representative errors], [InvalidDuration(), InvalidLaunchTime()])
  #parbreak()
  #field([Meaning], [Requested sale timing must fit the global schedule bounds.])
])

#card([Commit path], [
  #field([Representative errors], [NotApproved(), NotActive(), AlreadyFinalized(), ZeroAmount(), InvalidCollateralTransfer(), InvalidCollateralBehavior()])
  #parbreak()
  #field([Meaning], [A commitment fails unless the raise is approved, within the active window, not finalized, and backed by exact collateral transfer behavior.])
])

#card([Finalization and settlement], [
  #field([Representative errors], [NotReady(), NothingToClaim(), AlreadyClaimed(), RefundNotAvailable(), AlreadyRefunded()])
  #parbreak()
  #field([Meaning], [Finalization and settlement functions are bound to explicit lifecycle states; claims and refunds are one-shot paths.])
])

#card([Executor policy], [
  #field([Representative errors], [TargetNotAllowed(), SelectorNotAllowed(), SpenderNotAllowed(), ExecutionFailed()])
  #parbreak()
  #field([Meaning], [Treasury calls through the module fail unless the operator, target, selector, and approval recipient all satisfy the configured policy.])
])

The system is not maximally trustless. It is a constrained-authority design in which admins control raise admission and treasury policy, the operator controls business execution inside that policy, and investors rely on bounded sale mechanics rather than on operator discretion for entry and exit.

== Operational Read and Write Surfaces

The most useful contract methods for integrations are the ones that compress state into operationally meaningful reads.

#card([AgentRaiseFactory], [
  #field([Method], [projectCount()])
  #parbreak()
  #field([Operational use], [Enumerate existing projects.])
])

#card([AgentRaiseFactory], [
  #field([Method], [getProject(projectId)])
  #parbreak()
  #field([Operational use], [Read project metadata together with canonical addresses for treasury, sale, executor, and collateral.])
])

#card([AgentRaiseFactory], [
  #field([Method], [getProjectRaiseSnapshot(projectId)])
  #parbreak()
  #field([Operational use], [Read the aggregate fundraising state in one call: approval, commitments, accepted amount, finalized flag, failed flag, active flag, timing, and vault address.])
])

#card([AgentRaiseFactory], [
  #field([Method], [getProjectCommitment(projectId, user)])
  #parbreak()
  #field([Operational use], [Read a user's recorded commitment through the factory rather than through a direct sale lookup.])
])

#card([AgentRaiseFactory], [
  #field([Method], [globalConfig(), minRaiseForCollateral(...), maxRaiseForCollateral(...)])
  #parbreak()
  #field([Operational use], [Validate client-side construction of creation flows and display collateral-specific thresholds.])
])

#card([Sale], [
  #field([Method], [getStatus()])
  #parbreak()
  #field([Operational use], [Read totalCommitted, acceptedAmount, finalized, and failed.])
])

#card([Sale], [
  #field([Method], [isActive(), timeRemaining(), startTime(), endTime()])
  #parbreak()
  #field([Operational use], [Drive countdown, liveness, and phase transitions in frontend, backend, or CLI interfaces.])
])

#card([Sale], [
  #field([Method], [getClaimable(user), getRefundable(user)])
  #parbreak()
  #field([Operational use], [Preview settlement outcomes before broadcasting transactions.])
])

#card([Sale], [
  #field([Method], [token()])
  #parbreak()
  #field([Operational use], [Discover the vault address after successful finalization.])
])

#card([AgentExecutor], [
  #field([Method], [allowlistEnforced(), isSelectorAllowed(target, selector)])
  #parbreak()
  #field([Operational use], [Inspect effective executor policy.])
])

#card([ContractAllowlist], [
  #field([Method], [isAllowed(target)])
  #parbreak()
  #field([Operational use], [Inspect whether a target or approval recipient is eligible when enforcement is active.])
])

== CLI Design by Persona

The current repository does not implement a production CLI, so the section below is prescriptive rather than descriptive. The aim is to define a thin operational layer that maps cleanly to current contract surfaces and remains useful even when different keys control creator, operator, and admin workflows.

The main design principle is that the CLI should not be centered on admin commands. Most day-to-day value comes from inspection, participation, settlement, and treasury operation.

=== CLI conventions

- proposed binary name: `Backed`
- optional machine-readable output through `--json`
- environment variables:
  - `RPC_URL`
  - `PRIVATE_KEY`
  - `FACTORY_ADDRESS`
  - `IDENTITY_REGISTRY_ADDRESS`
  - `ALLOWLIST_ADDRESS`

=== 1. Observer and analyst commands

#card([Backed raise list], [
  #field([Primary on-chain mapping], [projectCount() plus getProject(...)])
  #parbreak()
  #field([Why it matters], [Enumerate projects without prior knowledge of IDs.])
])

#card([Backed raise show --project-id <id>], [
  #field([Primary on-chain mapping], [getProject(projectId)])
  #parbreak()
  #field([Why it matters], [Display canonical project addresses and metadata.])
])

#card([Backed raise snapshot --project-id <id>], [
  #field([Primary on-chain mapping], [getProjectRaiseSnapshot(projectId)])
  #parbreak()
  #field([Why it matters], [Read the full fundraising snapshot in one command.])
])

#card([Backed raise commitment --project-id <id> --user <addr>], [
  #field([Primary on-chain mapping], [getProjectCommitment(projectId, user)])
  #parbreak()
  #field([Why it matters], [Inspect a single investor position.])
])

#card([Backed sale status --sale <address>], [
  #field([Primary on-chain mapping], [Sale.getStatus()])
  #parbreak()
  #field([Why it matters], [Read raw sale totals and terminal flags directly from the sale.])
])

#card([Backed sale preview-claim --sale <address> --user <addr>], [
  #field([Primary on-chain mapping], [Sale.getClaimable(user)])
  #parbreak()
  #field([Why it matters], [Estimate post-success shares and overflow refund.])
])

#card([Backed sale preview-refund --sale <address> --user <addr>], [
  #field([Primary on-chain mapping], [Sale.getRefundable(user)])
  #parbreak()
  #field([Why it matters], [Estimate failure-path refund value.])
])

#card([Backed treasury policy --executor <address> --target <addr> --selector <0x...>], [
  #field([Primary on-chain mapping], [allowlistEnforced(), isAllowed(...), isSelectorAllowed(...)])
  #parbreak()
  #field([Why it matters], [Explain why an operator call will succeed or fail before broadcast.])
])

=== 2. Founder and project-owner commands

#card([Backed agent register --uri <agent-uri>], [
  #field([Primary on-chain mapping], [Deployment-specific registry write outside the in-repo interface])
  #parbreak()
  #field([Why it matters], [Acquire or register the identity used as the root credential for createAgentRaise(...).])
])

#card([Backed raise create --agent-id ... --name ... --description ... --categories ... --agent-operator ... --collateral ... --duration ... --launch-time ... --token-name ... --token-symbol ...], [
  #field([Primary on-chain mapping], [AgentRaiseFactory.createAgentRaise(...)])
  #parbreak()
  #field([Why it matters], [Create the project envelope in one transaction.])
])

#card([Backed raise config --collateral <address>], [
  #field([Primary on-chain mapping], [globalConfig(), minRaiseForCollateral(...), maxRaiseForCollateral(...)])
  #parbreak()
  #field([Why it matters], [Preview duration and raise constraints before signing a creation transaction.])
])

#card([Backed raise addresses --project-id <id>], [
  #field([Primary on-chain mapping], [getProject(projectId)])
  #parbreak()
  #field([Why it matters], [Extract treasury, sale, and agentExecutor immediately after creation.])
])

#card([Backed raise set-status --project-id <id> --status <n> --note <text>], [
  #field([Primary on-chain mapping], [updateProjectOperationalStatus(...)])
  #parbreak()
  #field([Why it matters], [Expose project-level signaling by the stored project creator or the factory admin.])
])

=== 3. Investor commands

#card([Backed investor approve --token <addr> --spender <sale> --amount <amount>], [
  #field([Primary on-chain mapping], [ERC-20 approve(address,uint256)])
  #parbreak()
  #field([Why it matters], [Prepare collateral allowance for the sale contract.])
])

#card([Backed investor commit --sale <address> --amount <amount>], [
  #field([Primary on-chain mapping], [Sale.commit(amount)])
  #parbreak()
  #field([Why it matters], [Enter an active raise.])
])

#card([Backed investor finalize --sale <address>], [
  #field([Primary on-chain mapping], [Sale.finalize()])
  #parbreak()
  #field([Why it matters], [Permissionless closure after endTime; useful for any participant, not only the founder.])
])

#card([Backed investor claim --sale <address>], [
  #field([Primary on-chain mapping], [Sale.claim()])
  #parbreak()
  #field([Why it matters], [Receive vault shares and any overflow refund after a successful raise.])
])

#card([Backed investor refund --sale <address>], [
  #field([Primary on-chain mapping], [Sale.refund()])
  #parbreak()
  #field([Why it matters], [Recover committed collateral after a failed or emergency-refunded raise.])
])

#card([Backed investor position --sale <address> --user <addr>], [
  #field([Primary on-chain mapping], [commitments(user), getClaimable(user), getRefundable(user)])
  #parbreak()
  #field([Why it matters], [Show the current position and all available settlement paths in one view.])
])

=== 4. Operator commands

#card([Backed operator exec --executor <address> --target <address> --calldata <0x...> [--value 0]], [
  #field([Primary on-chain mapping], [AgentExecutor.execute(...)])
  #parbreak()
  #field([Why it matters], [Raw treasury call surface for the authorized operator.])
])

#card([Backed operator exec-sig --executor <address> --target <address> --signature "fn(...)" --args ...], [
  #field([Primary on-chain mapping], [AgentExecutor.execute(...)])
  #parbreak()
  #field([Why it matters], [ABI-aware wrapper that removes manual calldata encoding.])
])

#card([Backed operator simulate --executor <address> --target <address> --signature "fn(...)" --args ...], [
  #field([Primary on-chain mapping], [Read policy plus ABI encoding])
  #parbreak()
  #field([Why it matters], [Preflight whether a call is blocked by target, selector, or approval-spender rules before signing.])
])

#card([Backed operator distribute-profits --executor <address> --collateral <address> --vault <address> --amount <amount>], [
  #field([Primary on-chain mapping], [Two execute(...) calls: collateral approval then distributeProfits(uint256)])
  #parbreak()
  #field([Why it matters], [Purpose-built wrapper for the canonical post-raise profit flow tested in the repo.])
])

#card([Backed operator vault --sale <address>], [
  #field([Primary on-chain mapping], [Sale.token()])
  #parbreak()
  #field([Why it matters], [Resolve the vault address from the sale before building treasury operations.])
])

=== 5. Governance appendix

These commands remain necessary, but they should be presented as a smaller governance surface rather than as the center of the CLI.

#card([Backed admin approve-raise --project-id <id>], [
  #field([Primary on-chain mapping], [AgentRaiseFactory.approveProject(projectId)])
  #parbreak()
  #field([Why it matters], [Open the raise for commitments.])
])

#card([Backed admin revoke-raise --project-id <id>], [
  #field([Primary on-chain mapping], [AgentRaiseFactory.revokeProject(projectId)])
  #parbreak()
  #field([Why it matters], [Stop new commitments while preserving already-committed state.])
])

#card([Backed admin allow-target --target <address>], [
  #field([Primary on-chain mapping], [ContractAllowlist.addContract(target)])
  #parbreak()
  #field([Why it matters], [Authorize an executor target when allowlist enforcement is active.])
])

#card([Backed admin deny-target --target <address>], [
  #field([Primary on-chain mapping], [ContractAllowlist.removeContract(target)])
  #parbreak()
  #field([Why it matters], [Remove a target from the global allowlist.])
])

#card([Backed admin allow-selector --executor <address> --target <address> --selector <0x...>], [
  #field([Primary on-chain mapping], [AgentExecutor.setSelectorAllowed(...)])
  #parbreak()
  #field([Why it matters], [Grant a selector on one executor instance.])
])

#card([Backed admin allow-selectors --executor <address> --target <address> --selectors <csv>], [
  #field([Primary on-chain mapping], [AgentExecutor.setSelectorsAllowed(...)])
  #parbreak()
  #field([Why it matters], [Batch selector setup for common policy bundles.])
])

#card([Backed admin set-allowlist --executor <address> --enabled <true|false>], [
  #field([Primary on-chain mapping], [AgentExecutor.setAllowlistEnforced(...)])
  #parbreak()
  #field([Why it matters], [Toggle policy enforcement for one executor.])
])

#card([Backed admin emergency-refund --sale <address>], [
  #field([Primary on-chain mapping], [Sale.emergencyRefund()])
  #parbreak()
  #field([Why it matters], [Force the sale into the failure path before standard finalization.])
])

=== Example command paths

Founder path:

```bash
Backed raise config --collateral 0xUSDM
Backed raise create \
  --agent-id 11 \
  --name "Backed Test Agent" \
  --description "Five-minute test raise for interface verification" \
  --categories "defi,ai,testing" \
  --agent-operator 0xAgentOperator \
  --collateral 0xUSDM \
  --duration 300 \
  --launch-time 1772290574 \
  --token-name "Backed Test Vault" \
  --token-symbol STV
Backed raise addresses --project-id 2
Backed raise snapshot --project-id 2
```

Investor path:

```bash
Backed investor approve --token 0xUSDM --spender 0xSale --amount 500000000000000000000
Backed investor commit --sale 0xSale --amount 500000000000000000000
Backed investor finalize --sale 0xSale
Backed investor position --sale 0xSale --user 0xInvestor
Backed investor claim --sale 0xSale
```

Operator path:

```bash
Backed treasury policy --executor 0xExec --target 0xUSDM --selector 0x095ea7b3
Backed operator distribute-profits \
  --executor 0xExec \
  --collateral 0xUSDM \
  --vault 0xVault \
  --amount 1000000000000000000000
```

In practice such a CLI should coexist with direct `cast call`, `cast send`, and `forge script` usage. That is already the operational style suggested in `docs/DEPLOY.md`, and it keeps the abstraction thin.

== Code References

- `src/agents/AgentRaiseFactory.sol`
- `src/launch/Sale.sol`
- `src/agents/AgentExecutor.sol`
- `src/token/AgentVaultToken.sol`
- `src/registry/ContractAllowlist.sol`
- `src/interfaces/IERC8004IdentityRegistry.sol`
- `docs/DEPLOY.md`
- `test/e2e/AgentRaiseE2E.t.sol`
- `test/e2e/AgentRaiseFlowMatrix.t.sol`
