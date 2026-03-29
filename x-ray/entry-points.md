# Entry Point Map

> Backed Agent Raise | 27 entry points | 4 permissionless | 6 role-gated | 16 admin-only

---

## Protocol Flow Paths

### Setup (Project creator + admin)

`createAgentRaise()` -> `approveProject()` -> `commit()`  ◄── sale window must open

### Investor flow

`[setup above]` -> `Sale.commit()`
                 ├─→ `Sale.finalize()`  ◄── `endTime` reached
                 │    ├─→ `Sale.claim()`   ◄── successful finalize
                 │    └─→ `Sale.refund()`  ◄── failed finalize

### Emergency flow

`[setup above]` -> `Sale.commit()` -> `Sale.emergencyRefund()` -> `Sale.refund()`

### Treasury operation

`[successful finalize above]` -> `ContractAllowlist.addContract()` / `AgentExecutor.setSelectorAllowed()`
                               -> `AgentExecutor.execute()`
                                  ├─→ collateral approval
                                  └─→ `AgentVaultToken.distributeProfits()`  ◄── treasury approved vault

### Module bootstrapping

`AgentRaiseFactory.createAgentRaise()` -> `_createSafe()` -> `SafeModuleSetup.enableModules()` -> `_setupSafeModules()`

---

## Permissionless

### `Sale.commit()`

| Aspect | Detail |
|--------|--------|
| Visibility | `external`, `nonReentrant` |
| Caller | User / investor |
| Parameters | `amount (user-controlled)` |
| Call chain | `-> IERC20.safeTransferFrom()` |
| State modified | `commitments`, `totalCommitted`, `participantCount` |
| Value flow | Tokens: user -> `Sale` |
| Reentrancy guard | yes |

### `Sale.finalize()`

| Aspect | Detail |
|--------|--------|
| Visibility | `external`, `nonReentrant` |
| Caller | Anyone |
| Parameters | none |
| Call chain | `-> AgentVaultToken.bootstrap() -> AgentVaultToken.completeSale()` |
| State modified | `finalized`, `failed`, `acceptedAmount`, `totalSharesMinted`, `_token` |
| Value flow | Tokens: `Sale` -> `AgentVaultToken` on success |
| Reentrancy guard | yes |

### `Sale.claim()`

| Aspect | Detail |
|--------|--------|
| Visibility | `external`, `nonReentrant` |
| Caller | Investor |
| Parameters | none |
| Call chain | `-> IERC20.safeTransfer()` |
| State modified | `claimed`, `claimedCount`, `totalAcceptedClaimed`, `totalSharesClaimed`, `totalRefundedAmount` |
| Value flow | Tokens: `Sale` -> investor (vault shares and optional overflow refund) |
| Reentrancy guard | yes |

### `Sale.refund()`

| Aspect | Detail |
|--------|--------|
| Visibility | `external`, `nonReentrant` |
| Caller | Investor |
| Parameters | none |
| Call chain | `-> IERC20.safeTransfer()` |
| State modified | `refunded` |
| Value flow | Tokens: `Sale` -> investor |
| Reentrancy guard | yes |

---

## Role-Gated

### `Project Creator`

#### `AgentRaiseFactory.createAgentRaise()`

| Aspect | Detail |
|--------|--------|
| Visibility | `external`, internal caller restriction |
| Caller | Project creator / identity owner |
| Parameters | `agentId (user-controlled but ownership-checked)`, `name (user-controlled)`, `description (user-controlled)`, `categories (user-controlled)`, `agentAddress (user-controlled)`, `collateral (user-controlled)`, `duration (user-controlled)`, `launchTime (user-controlled)`, `tokenName (user-controlled)`, `tokenSymbol (user-controlled)` |
| Call chain | `-> IDENTITY_REGISTRY.ownerOf() -> _createSafe() -> ISafeProxyFactory.createProxyWithNonce() -> new Sale() -> new AgentExecutor() -> _setupSafeModules()` |
| State modified | `_projects`, `_agentProjects` |
| Value flow | None |
| Reentrancy guard | no |

### `Project Operator (stored project.agent or admin)`

#### `AgentRaiseFactory.updateProjectOperationalStatus()`

| Aspect | Detail |
|--------|--------|
| Visibility | `external`, `onlyProjectOperator(projectId)` |
| Caller | Stored project agent or admin |
| Parameters | `projectId (user-controlled)`, `status (user-controlled)`, `statusNote (user-controlled)` |
| Call chain | none |
| State modified | `operationalStatus`, `statusNote`, `updatedAt` in `AgentProject` |
| Value flow | None |
| Reentrancy guard | no |

### `AGENT`

#### `AgentExecutor.execute()`

| Aspect | Detail |
|--------|--------|
| Visibility | `external`, `nonReentrant`, `onlyAgent` |
| Caller | Agent operator |
| Parameters | `target (user-controlled)`, `value (user-controlled)`, `data (user-controlled)` |
| Call chain | `-> _enforcePolicy() -> ISafe.execTransactionFromModuleReturnData()` |
| State modified | none in protocol storage |
| Value flow | Tokens/ETH: `TREASURY` -> target, depending on calldata |
| Reentrancy guard | yes |

### `SALE`

#### `AgentVaultToken.bootstrap()`

| Aspect | Detail |
|--------|--------|
| Visibility | `external`, internal caller restriction |
| Caller | `Sale` |
| Parameters | `assets (protocol-derived)`, `receiver (protocol-derived)` |
| Call chain | `-> IERC20.safeTransferFrom() -> _mint()` |
| State modified | `bootstrapped` |
| Value flow | Tokens: `Sale` -> `AgentVaultToken` |
| Reentrancy guard | no |

#### `AgentVaultToken.completeSale()`

| Aspect | Detail |
|--------|--------|
| Visibility | `external`, internal caller restriction |
| Caller | `Sale` |
| Parameters | none |
| Call chain | none |
| State modified | `saleCompleted` |
| Value flow | None |
| Reentrancy guard | no |

### `TREASURY`

#### `AgentVaultToken.distributeProfits()`

| Aspect | Detail |
|--------|--------|
| Visibility | `external`, internal caller restriction |
| Caller | Safe treasury through executor/module path |
| Parameters | `grossAmount (protocol-derived or operator-provided through executor calldata)` |
| Call chain | `-> IERC20.safeTransferFrom()` |
| State modified | none in storage; emits accounting event only |
| Value flow | Tokens: `TREASURY` -> `PLATFORM_FEE_RECIPIENT` and `AgentVaultToken` |
| Reentrancy guard | no |

---

## Admin-Only

| Contract | Function | Parameters | State Modified |
|----------|----------|------------|----------------|
| `AgentRaiseFactory` | `approveProject()` | `projectId` | `projectApproved` |
| `AgentRaiseFactory` | `revokeProject()` | `projectId` | `projectApproved` |
| `AgentRaiseFactory` | `setGlobalConfig()` | `config_` | `globalConfig` |
| `AgentRaiseFactory` | `setAllowedCollateral()` | `collateral`, `allowed` | `allowedCollateral` |
| `AgentRaiseFactory` | `updateProjectMetadata()` | `projectId`, `description`, `categories` | `AgentProject.description`, `AgentProject.categories`, `updatedAt` |
| `AgentExecutor` | `setAllowlistEnforced()` | `enforced` | `allowlistEnforced` |
| `AgentExecutor` | `setSelectorAllowed()` | `target`, `selector`, `allowed` | `isSelectorAllowed[target][selector]` |
| `AgentExecutor` | `setSelectorsAllowed()` | `target`, `selectors`, `allowed` | `isSelectorAllowed[target][selector]` for each selector |
| `Sale` | `emergencyRefund()` | none | `finalized`, `failed` |
| `ContractAllowlist` | `addContract()` | `target` | `isAllowed[target]` |
| `ContractAllowlist` | `removeContract()` | `target` | `isAllowed[target]` |
| `ContractAllowlist` | `addContracts()` | `targets` | `isAllowed[target]` for each target |
| `ContractAllowlist` | `removeContracts()` | `targets` | `isAllowed[target]` for each target |
| `ContractAllowlist` | `transferAdmin()` | `newAdmin` | `admin` |
| `DexRegistry` | `addDex()` | `v3Factory`, `positionManager`, `swapRouter` | `_dexes`, `dexCount` |
| `DexRegistry` | `deactivateDex()` | `dexId` | `_dexes[dexId].active` |

---

## Initialization

### `SafeModuleSetup.enableModules()`

| Aspect | Detail |
|--------|--------|
| Visibility | `external` |
| Caller | Safe setup flow |
| Parameters | `modules (protocol-derived during deployment)` |
| Call chain | `-> _enableModule() -> address(this).call(enableModule(address))` |
| State modified | none in helper storage |
| Value flow | None |
| Reentrancy guard | no |

This helper is part of the deployment path and is intended to run in the Safe setup context rather than as a user-facing runtime entry point.
