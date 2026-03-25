# How to Create an Agent Raise

## Purpose

This guide explains how to create an agent fundraising project using the current `AgentRaiseFactory` flow.

## End-to-End Process

1. Register an ERC-8004 agent identity.
2. Confirm ownership of the returned `agentId`.
3. Call `createAgentRaise(...)` on `AgentRaiseFactory`.
4. Wait for admin approval (`approveProject`).
5. Investors commit during the sale window.

## Step 1: Register Agent Identity

Before creating a raise, the wallet must own an ERC-8004 identity token.

```solidity
// Identity Registry (ERC-8004)
function register(string calldata agentURI) external returns (uint256 agentId)
```

Inputs:

- `agentURI`: IPFS/HTTP URI pointing to the agent registration metadata.

## Step 2: Create the Raise

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

Parameter requirements:

- `agentId`: caller must own this ERC-8004 token.
- `name`: must be non-empty.
- `agentAddress`: must be non-zero.
- `collateral`: must be enabled by factory admin.
- `duration`: must satisfy global config bounds.
- `launchTime`: must be in the future and within launch delay bounds.

## Validation Rules

`createAgentRaise` enforces:

1. `IDENTITY_REGISTRY.ownerOf(agentId) == msg.sender`
2. `bytes(name).length > 0`
3. `agentAddress != address(0)`
4. `allowedCollateral[collateral] == true`
5. `duration` in `[minDuration, maxDuration]`
6. `launchTime >= block.timestamp`
7. `launchDelay` in `[minLaunchDelay, maxLaunchDelay]`

## Common Errors

- `NotAgentOwner()`: caller does not own `agentId`.
- `InvalidParams()`: empty name or zero duration/launch time.
- `InvalidAddress()`: zero address provided.
- `UnsupportedCollateral()`: collateral not allowlisted.
- `InvalidDuration()`: duration out of bounds.
- `InvalidLaunchTime()`: invalid start time or delay.
- `InvalidConfig()`: inconsistent factory configuration.

## Frontend Integration Checklist

Before calling `createAgentRaise`:

- read `ownerOf(agentId)` and compare with connected wallet
- read `allowedCollateral(collateral)`
- read `globalConfig()`
- validate `duration` and `launchDelay` client-side
- simulate transaction with the same account that will sign

## Practical Fix for `InvalidParams()`

If you encounter `InvalidParams()`:

- ensure `name` is not empty
- ensure `duration > 0`
- ensure `launchTime > 0` and in the future

## Post-Creation

After `projectId` is created:

- admin must call `approveProject(projectId)` before commitments are accepted
- monitor sale status via project and sale view functions
