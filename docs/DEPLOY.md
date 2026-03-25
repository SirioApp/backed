# Deployment Guide

Comprehensive deployment and post-deployment operations guide for the current Sirio backend contracts on MegaETH.

## Prerequisites

- `PRIVATE_KEY` available in environment.
- Sufficient ETH balance for deployment gas.
- Correct network RPC endpoint.

Example:

```bash
export PRIVATE_KEY=0x...
```

## Build

```bash
cd backend
forge build
```

## Network Configuration

- Testnet chain ID: `6343`
- Mainnet chain ID: `4326`
- Testnet RPC: `https://carrot.megaeth.com/rpc`
- Mainnet RPC: `https://mainnet.megaeth.com/rpc`

## Recommended Deployment Commands

### Testnet factory stack

```bash
cd backend
NO_PROXY="*" forge script script/DeployFactoryStackTestnet.s.sol:DeployFactoryStackTestnet \
  --rpc-url megaeth-testnet \
  --broadcast \
  --gas-estimate-multiplier 5000 \
  --code-size-limit 100000 \
  -vvv
```

Deploys:

- `SafeModuleSetup`
- `ContractAllowlist`
- `AgentRaiseFactory`

### Mainnet factory refresh

```bash
cd backend
NO_PROXY="*" forge script script/DeployNewAgentRaiseFactory.s.sol:DeployNewAgentRaiseFactory \
  --rpc-url megaeth-mainnet \
  --broadcast \
  --gas-estimate-multiplier 5000 \
  --code-size-limit 100000 \
  -vvv
```

### Mainnet DEX registry

```bash
cd backend
NO_PROXY="*" forge script script/DeployDexRegistry.s.sol:DeployDexRegistry \
  --rpc-url megaeth-mainnet \
  --broadcast \
  --gas-estimate-multiplier 5000 \
  --code-size-limit 100000 \
  -vvv
```

### Register agent identity

```bash
cd backend
export AGENT_URI="ipfs://your-agent-metadata"
NO_PROXY="*" forge script script/RegisterAgent.s.sol:RegisterAgent \
  --rpc-url megaeth-mainnet \
  --broadcast \
  -vvv
```

## Why These Flags

- `NO_PROXY="*"`: avoids local proxy-related RPC issues.
- `--gas-estimate-multiplier 5000`: aligns with MegaETH estimation behavior.
- `--code-size-limit 100000`: aligns with target deployment constraints.

## Post-Deployment Steps

1. Record deployed addresses.
2. Update:
   - `deployments/megaeth-testnet.json`
   - `deployments/megaeth-mainnet.json`
3. Sync deployment artifacts to downstream services (frontend/indexer).
4. Verify functional health checks (factory reads, project creation, approval flow).

## Suggested Validation Commands

```bash
# Project count
cast call <FACTORY> "projectCount()(uint256)" --rpc-url <RPC>

# Global config
cast call <FACTORY> "globalConfig()(uint256,uint256,uint16,address,uint256,uint256,uint256,uint256)" --rpc-url <RPC>
```

## Troubleshooting

### `Attempted to create a NULL object`

Use `NO_PROXY="*"` in the command environment.

### `Contract size limit exceeded`

Use `--code-size-limit 100000`.

### Gas estimation failures

Increase `--gas-estimate-multiplier`.

### `IO error: not a terminal`

This message may be non-fatal depending on terminal/runtime context.

## Operational Checklist

- [ ] Build succeeds (`forge build`).
- [ ] Deployment transaction(s) confirmed.
- [ ] Deployment artifact JSON updated.
- [ ] Integration sync completed.
- [ ] Critical read calls validated on target network.
