# Debug Guide: `createAgentRaise` Reverts

## Problem Statement

A common issue is a revert during `createAgentRaise(...)`, often observed as `NotAgentOwner()` or generic simulation failure.

## Root Causes

Most failures come from one of the following:

1. The simulation `account` is not the actual owner of `agentId`.
2. `launchTime` is stale or already in the past at execution time.
3. `duration` is outside global config limits.
4. `collateral` is not enabled in the factory.
5. Required fields are empty or invalid.

## Quick Verification Sequence

### 1. Verify ownership on-chain

```typescript
const owner = await publicClient.readContract({
  address: IDENTITY_REGISTRY,
  abi: IdentityRegistryABI,
  functionName: 'ownerOf',
  args: [agentId]
});

if (owner.toLowerCase() !== account.address.toLowerCase()) {
  throw new Error('Account does not own this agentId');
}
```

### 2. Verify simulation account

```typescript
await publicClient.simulateContract({
  account: account.address, // must match ownerOf(agentId)
  address: FACTORY,
  abi: AgentRaiseFactoryABI,
  functionName: 'createAgentRaise',
  args: [...]
});
```

### 3. Compute launch time dynamically

```typescript
const now = Math.floor(Date.now() / 1000);
const launchDelay = 3600; // example: 1 hour
const launchTime = now + launchDelay;
```

### 4. Validate config constraints

```typescript
const cfg = await publicClient.readContract({
  address: FACTORY,
  abi: AgentRaiseFactoryABI,
  functionName: 'globalConfig'
});

if (duration < Number(cfg.minDuration) || duration > Number(cfg.maxDuration)) {
  throw new Error('Invalid duration');
}
if (launchDelay < Number(cfg.minLaunchDelay) || launchDelay > Number(cfg.maxLaunchDelay)) {
  throw new Error('Invalid launch delay');
}
```

### 5. Validate collateral

```typescript
const isAllowed = await publicClient.readContract({
  address: FACTORY,
  abi: AgentRaiseFactoryABI,
  functionName: 'allowedCollateral',
  args: [collateral]
});

if (!isAllowed) throw new Error('Collateral not enabled');
```

## CLI Checks

```bash
# Check owner
cast call <IDENTITY_REGISTRY> "ownerOf(uint256)(address)" <AGENT_ID> --rpc-url <RPC>

# Check collateral policy
cast call <FACTORY> "allowedCollateral(address)(bool)" <COLLATERAL> --rpc-url <RPC>

# Read global config
cast call <FACTORY> "globalConfig()(uint256,uint256,uint16,address,uint256,uint256,uint256,uint256)" --rpc-url <RPC>
```

## Recommended Debug Checklist

- [ ] Simulation `account` equals `ownerOf(agentId)`.
- [ ] `launchTime` is generated at runtime and strictly in the future.
- [ ] `duration` passes global bounds.
- [ ] `launchDelay` passes global bounds.
- [ ] `collateral` is enabled in factory.
- [ ] `name` is non-empty.
- [ ] `agentAddress` is non-zero.
