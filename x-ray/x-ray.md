# X-Ray Report

> Backed Agent Raise | 1087 nSLOC | 04f6cdd (`main`) | foundry | 29/03/26

---

## 1. Protocol Overview

**What it does:** Launches identity-gated agent raises that deploy a Safe treasury, run a capped collateral sale, mint fixed-supply vault shares on success, and let an operator use treasury funds through a policy-constrained Safe module.

- **Users**: project creators launch raises, investors commit collateral and settle into shares or refunds, operators execute approved treasury actions, admins gate fundraising and policy.
- **Core flow**: creator calls `AgentRaiseFactory.createAgentRaise()` -> admin approves -> investors commit into `Sale` -> anyone finalizes -> success bootstraps `AgentVaultToken` -> operator executes treasury flows through `AgentExecutor`.
- **Key mechanism**: capped sale feeding a fixed-supply ERC4626 vault, with post-raise treasury execution mediated by a Safe module plus target/selector policy.
- **Token model**: one external collateral token enters `Sale`; on success a fixed-supply `AgentVaultToken` is minted once and later accrues value through `distributeProfits()`.
- **Admin model**: a single factory admin controls raise approval and global config; executor admin controls per-project selector policy; allowlist admin controls globally allowed targets.

For a visual overview of the protocol's architecture, see the [architecture diagram](architecture.svg).

### Contracts in Scope

| Subsystem | Key Contracts | nSLOC | Role |
|-----------|--------------|------:|------|
| Origination | `AgentRaiseFactory`, `SafeModuleSetup`, `Constants` | 423 | Validates raises, deploys project envelopes, wires Safe modules, stores global and per-project state |
| Fundraising | `Sale` | 245 | Accepts commitments, finalizes outcomes, handles claims, refunds, and emergency failure |
| Treasury Policy | `AgentExecutor`, `ContractAllowlist` | 173 | Restricts treasury execution by caller, target, selector, and approval recipient |
| Vault | `AgentVaultToken` | 95 | Holds accepted collateral, mints fixed share supply once, and receives profits from treasury |
| Auxiliary Registry | `DexRegistry` | 45 | Admin-managed DEX config registry, currently separate from the raise flow |

### How It Fits Together

The core trick: the system splits project birth, fundraising, capitalization, and treasury operation into separate contracts so investor state resolution and operator treasury powers can be reasoned about independently.

### Project creation

```text
Project creator
└─ AgentRaiseFactory.createAgentRaise()
   ├─ IDENTITY_REGISTRY.ownerOf(agentId)
   ├─ _createSafe()
   │  └─ ISafeProxyFactory.createProxyWithNonce()
   ├─ new Sale(...)
   ├─ new AgentExecutor(...)
   └─ _setupSafeModules()
      ├─ Safe.enableModule(executor)
      └─ Safe.disableModule(factory)
```

*Critical step: the factory removes itself from the Safe module list after setup, leaving runtime execution to the project-specific executor.*

### Fundraising and settlement

```text
Investor
└─ Sale.commit(amount)
   ├─ FACTORY.isProjectApproved(PROJECT_ID)
   ├─ COLLATERAL.safeTransferFrom(user -> sale)
   └─ commitments[user] / totalCommitted updated

Anyone
└─ Sale.finalize()
   ├─ acceptedAmount = min(totalCommitted, MAX_RAISE)
   ├─ if acceptedAmount < MIN_RAISE -> failed
   └─ else
      ├─ new AgentVaultToken(...)
      ├─ vault.bootstrap(acceptedAmount, sale)
      └─ vault.completeSale()
```

*Critical step: oversubscription is resolved at claim time, not commit time; accepted capital is capped, while overflow stays in `Sale` for pro-rata refunds.*

### Treasury profit flow

```text
Admin
└─ ContractAllowlist / AgentExecutor policy setup

Operator
└─ AgentExecutor.execute(collateral, 0, approve(vault, amount))
   └─ Safe.execTransactionFromModuleReturnData()

Operator
└─ AgentExecutor.execute(vault, 0, distributeProfits(amount))
   └─ Safe.execTransactionFromModuleReturnData()
      └─ AgentVaultToken.distributeProfits()
         ├─ fee -> PLATFORM_FEE_RECIPIENT
         └─ net assets -> vault
```

*Critical step: `distributeProfits()` pulls funds from the treasury and is callable only by the treasury itself, so the executor must route the call through the Safe module path.*

---

## 2. Threat & Trust Model

### Protocol Threat Profile

> Protocol classified as: **Yield Aggregator** with **fundraising / treasury-management** characteristics

The code matches a vault-style share accounting model because value ultimately accrues in `AgentVaultToken` through fixed-supply shares and `distributeProfits()`. The threat model is additionally shaped by the sale lifecycle and by the Safe-module treasury execution boundary in `Sale` and `AgentExecutor`.

### Actors & Adversary Model

| Actor | Trust Level | Capabilities |
|-------|-------------|-------------|
| Project creator | Bounded (must own `agentId`, can only affect their own project metadata/status) | Can create raises and update operational status for their stored `project.agent` address |
| Investor | Bounded (permissionless but constrained by sale state) | Can commit during active windows, finalize after `endTime`, and settle via `claim()` / `refund()` |
| Agent operator | Bounded (hard-coded per project, restricted by executor policy) | Can execute treasury calls through `AgentExecutor.execute()`; operations are instant once policy is configured |
| Factory admin | Trusted | Can approve/revoke raises, change global config, enable collateral, update metadata, and trigger sale emergency failure via `SUPER_ADMIN()` powers |
| Executor admin | Trusted | Can instantly toggle allowlist enforcement and set per-executor selector permissions |
| Allowlist admin | Trusted | Can instantly expand or shrink the global target allowlist shared across executors |

**Adversary Ranking** (ordered by threat level for this protocol type, adjusted by git evidence):

1. **Compromised admin** — Dominant risk because raise admission, emergency failure, target allowlisting, and selector policy all sit behind privileged roles with instant operational effects.
2. **Share-accounting attacker** — Relevant because successful raises resolve into fixed-supply ERC4626 shares with rounding-sensitive claim distribution and asset-accretion economics.
3. **Malicious or compromised operator** — Relevant because treasury execution is delegated to a single immutable `AGENT` per project and routes real treasury value through arbitrary approved call targets.
4. **Non-standard collateral attacker** — Relevant because the protocol depends on exact ERC20 transfer semantics during `commit()`, `bootstrap()`, and `distributeProfits()`.

See [entry-points.md](entry-points.md) for the full permissionless entry point map.

### Trust Boundaries

- **Identity boundary**: `AgentRaiseFactory.createAgentRaise()` trusts `IDENTITY_REGISTRY.ownerOf(agentId)` as the root authorization check. If the registry lies or its ownership model changes unexpectedly, project origination rights can be misassigned.
- **Admin boundary**: `AgentRaiseFactory`, `AgentExecutor`, and `ContractAllowlist` split privileged control across three contracts. Operational actions are instant; there is no timelock or multisig enforced in code. *Git signal: both source commits touch access control surfaces.*
- **Sale outcome boundary**: `Sale.finalize()` is permissionless, but `emergencyRefund()` is fully admin-driven. Investor recovery is bounded by explicit failure flags rather than by operator cooperation.
- **Treasury boundary**: `AgentExecutor` protects the Safe with hard-blocked targets and optional allowlist enforcement, but `setAllowlistEnforced(false)` collapses target, selector, and approval-recipient checks at once.

### Key Attack Surfaces

- **Sale accounting and settlement math** — `Sale.commit()`, `finalize()`, and `claim()` combine exact-transfer assumptions, hard caps, and last-claimer reconciliation. This is the main place where accounting drift or rounding edge cases would become user-visible.
- **Admin operational powers without delay** — `approveProject()`, `revokeProject()`, `setGlobalConfig()`, `setAllowedCollateral()`, `setAllowlistEnforced()`, and allowlist mutations all execute immediately and directly shape both fundraising and treasury safety.
- **Executor break-glass path** — `AgentExecutor.setAllowlistEnforced(false)` changes the trust model materially because the operator can then call arbitrary targets except three hard-blocked addresses.
- **Module bootstrapping path** — `AgentRaiseFactory._setupSafeModules()` and `SafeModuleSetup.enableModules()` are one-time setup code that determine whether the factory successfully exits the Safe and whether the executor becomes the sole module.
- **Collateral behavior assumptions** — `Sale.commit()`, `AgentVaultToken.bootstrap()`, and `AgentVaultToken.distributeProfits()` all assume exact transfer amounts and revert otherwise, making token behavior compatibility a first-order integration boundary.

### Protocol-Type Concerns

**As a Yield Aggregator:**
- `AgentVaultToken.bootstrap()` mints a fixed supply once and disables `deposit()` / `mint()`, so share-value correctness is entirely downstream of `Sale.claim()` allocation and `totalAssets()` growth.
- `Sale.claim()` uses residual distribution for the last claimer, so auditors should verify that `totalAcceptedClaimed`, `totalSharesClaimed`, and `totalRefundedAmount` close exactly under oversubscription.
- `AgentVaultToken.distributeProfits()` uses `safeTransferFrom` plus balance-delta validation, so direct collateral behavior and treasury approvals are part of the vault's effective accounting model.

### Temporal Risk Profile

**Deployment & Initialization:**
- `AgentRaiseFactory.createAgentRaise()` performs Safe deployment, sale deployment, executor deployment, and module rewiring in one path; any setup regression changes the runtime trust model immediately. Mitigation status: partially mitigated by atomic setup and tests, but there is no staged deployment safeguard.
- `Sale.finalize()` bootstraps the vault only after the sale window closes, so the protocol has an empty-state transition where no share token exists before success and all investor state lives in `Sale`. Mitigation status: explicit state flags exist, but this transition remains a core lifecycle boundary.

### Composability & Dependency Risks

**Dependency Risk Map:**

> **Identity registry** — via `AgentRaiseFactory.createAgentRaise()`
> - Assumes: `ownerOf(agentId)` accurately reflects the authorized creator
> - Validates: nonzero addresses and direct equality with `msg.sender`
> - Mutability: external dependency; behavior can change outside this repo
> - On failure: reverts project creation

> **Collateral token** — via `Sale.commit()`, `AgentVaultToken.bootstrap()`, `AgentVaultToken.distributeProfits()`
> - Assumes: exact transfer amounts, sane decimals, no hidden rebasing during transfer windows
> - Validates: balance-delta checks and decimals probing
> - Mutability: token behavior may change if the collateral is upgradeable or administratively controlled
> - On failure: reverts and blocks commitments / bootstrap / profit distribution

> **Safe treasury** — via `AgentExecutor.execute()`
> - Assumes: `execTransactionFromModuleReturnData()` honors module semantics and call forwarding as expected
> - Validates: success flag only; target-level policy is enforced in `AgentExecutor`
> - Mutability: external dependency, though instantiated through known Safe setup flow
> - On failure: reverts treasury execution

**Token Assumptions** *(unvalidated only)*:
- Blacklistable or pausable collateral would introduce a governance dependency outside this protocol's control, even though transfer amount exactness is checked internally.

---

## 3. Invariants

### Stated Invariants

- `AgentExecutor` forbids targeting the treasury, itself, or the allowlist contract. Source: `src/agents/AgentExecutor.sol`.
- `Sale` only accepts commitments during an approved active window and only when received collateral equals requested collateral. Source: `src/launch/Sale.sol`.
- `AgentVaultToken` bootstraps once, mints fixed supply once, and disables future share issuance via `deposit()` and `mint()`. Source: `src/token/AgentVaultToken.sol`.

### Inferred Invariants

- **Factory exits Safe module set**: after `createAgentRaise()`, the factory should no longer retain module execution rights on the project Safe. Derived from `AgentRaiseFactory._setupSafeModules()`. If violated: the deployment contract would retain unexpected runtime power.
- **Accepted capital never exceeds `MAX_RAISE`**: all successful capital formation is bounded by `acceptedAmount = min(totalCommitted, MAX_RAISE)`. Derived from `Sale.finalize()`. If violated: oversubscription handling and refund accounting break.
- **Claimed shares plus refunded overflow should fully close**: the combination of `totalSharesClaimed`, `totalAcceptedClaimed`, and `totalRefundedAmount` should exhaust the successful sale state after all participants settle. Derived from `Sale.claim()`. If violated: dust or value leakage remains trapped.
- **Executor policy is conjunctive when enabled**: allowed caller + allowed target + allowed selector + allowed spender are all required when `allowlistEnforced` is true. Derived from `AgentExecutor.execute()` and `_enforcePolicy()`. If violated: treasury call restrictions become bypassable.

---

## 4. Documentation Quality

| Aspect | Status | Notes |
|--------|--------|-------|
| README | Present | `README.md` |
| NatSpec | ~12 annotations | Core contracts have top-level NatSpec, but many lifecycle details still live only in code |
| Spec/Whitepaper | Missing | No whitepaper/spec/design/protocol document detected by the skill scan |
| Inline Comments | Adequate | Enough comments to explain setup flow and vault behavior, but not enough to replace code reading |

---

## 5. Test Analysis

| Metric | Value | Source |
|--------|-------|--------|
| Test files | 15 | File scan (always reliable) |
| Test functions | 136 | File scan (always reliable) |
| Line coverage | Unavailable — `forge: command not found` | Coverage tool (requires compilation) |
| Branch coverage | Unavailable — `forge: command not found` | Coverage tool (requires compilation) |

15 test files with 136 test functions were detected; coverage metrics are unavailable because the Foundry toolchain is not installed in this environment. This does not imply that tests are absent.

### Test Depth

| Category | Count | Contracts Covered |
|----------|-------|-------------------|
| Unit | 136 | broad |
| Stateless Fuzz | 0 | none |
| Stateful Fuzz (Foundry) | 0 | none |
| Formal Verification (any tool) | 0 | none |

### Gaps

- No stateless fuzz targets were detected despite arithmetic-heavy allocation and accounting logic in `Sale` and `AgentVaultToken`.
- No stateful invariant tests were detected for lifecycle transitions such as approval -> commit -> finalize -> claim/refund.
- No formal verification artifacts were detected for executor policy enforcement or share-allocation closure.

---

## 6. Developer & Git History

> Repo shape: squashed_import — only 2 source-touching commits over 4 days, so historical evolution signals are shallow and should be treated cautiously.

### Contributors

| Author | Commits | Source Lines (+/-) | % of Source Changes |
|--------|--------:|--------------------|--------------------:|
| lucatropea | 2 | +1497 / -61 | 100% |

### Review & Process Signals

| Signal | Value | Assessment |
|--------|-------|------------|
| Unique contributors | 1 | Single-dev |
| Merge commits | 0 of 2 (0%) | No merge commits — likely no peer review |
| Repo age | 2026-03-25 -> 2026-03-29 | 4 days |
| Recent source activity (30d) | 2 commits | Late burst before audit |
| Test co-change rate | 100% | Source-changing commits also touched tests; this measures co-modification, not coverage |

### File Hotspots

| File | Modifications | Note |
|------|-------------:|------|
| `src/token/AgentVaultToken.sol` | 2 | Core accounting path changed in both source commits |
| `src/launch/Sale.sol` | 2 | Central sale lifecycle and settlement logic |
| `src/agents/AgentRaiseFactory.sol` | 2 | Deploys all project envelopes and governs approvals |
| `src/agents/AgentExecutor.sol` | 2 | Treasury execution policy changed in both source commits |
| `src/registry/ContractAllowlist.sol` | 2 | Shared policy registry changed in both source commits |

### Dangerous Area Evolution

Minimal development history is visible, but both source commits touch all four sensitive domains surfaced by the git analysis: `access_control`, `fund_flows`, `signatures`, and `state_machines`.

### Security Observations

- Single-developer ownership is total: one author accounts for 100% of source changes.
- No merge commits are present, so there is no visible evidence of code review in git history.
- The whole audited surface is effectively “late change” code because both source commits fall inside the last 30 days.
- The most sensitive contracts (`AgentRaiseFactory`, `Sale`, `AgentExecutor`, `AgentVaultToken`) are also the highest-churn files in the tiny visible history.
- Test files co-changed with source in both commits, which is a positive structural signal, but there is still no evidence of fuzzing, invariants, or formal methods.

### Cross-Reference Synthesis

- `Sale.sol` is both a top hotspot and the main accounting surface in Section 2, so oversubscription and claim closure deserve deep review first.
- `AgentExecutor.sol` and `ContractAllowlist.sol` sit at the intersection of access-control churn and the treasury execution attack surface.
- `AgentVaultToken.sol` changed in both source commits and anchors the protocol's yield-aggregator classification, so fixed-supply accounting assumptions merit focused validation.

---

## X-Ray Verdict

**FRAGILE** — The codebase is compact and structurally coherent, but its assurance posture is limited by unit-test-only evidence, no visible review process, and instant privileged operational powers without in-code delay controls.

**Structural facts:**
1. 1087 nSLOC are concentrated in 5 subsystems, with most complexity in `AgentRaiseFactory`, `Sale`, and `AgentExecutor`.
2. 15 test files with 136 test functions were detected, but no fuzz, invariant, or formal verification artifacts were found.
3. Git history shows a single contributor, zero merge commits, and only 2 source-touching commits on the analyzed branch (`main` at `04f6cdd`).
4. Privileged controls are split across factory admin, executor admin, and allowlist admin, but all operational powers execute instantly in the current code.
