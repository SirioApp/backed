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

## Official Deployments

### Official Deployer / Admin

- `0xB7a43F5475898Ae787f782FE638FfaB18D6b2fb4`

### Testnet

- Deployed at: `2026-04-24`
- `SafeModuleSetup`: `0x7b6EbB0ede8ac0224a176663e6c07Dece0a37010`
- `ContractAllowlist`: `0x54459A9431bD98c754180DEB32B067Cf31bDfF33`
- `AgentRaiseFactory`: `0x577be362178d20A3370722807d0294fA5D8A5a2A`
- `USDM`: `0x9f5A17BD53310D012544966b8e3cF7863fc8F05f`
- `SafeProxyFactory`: `0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67`
- `SafeSingleton`: `0x29fcB43b46531BcA003ddC8FCB67FFE91900C762`
- `SafeFallbackHandler`: `0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99`
- `ERC8004 IdentityRegistry`: `0x8004A818BFB912233c491871b3d84c89A494BD9e`
- `ERC8004 ReputationRegistry`: `0x8004B663056A597Dffe9eCcC1965A193B7388713`

### Mainnet

- Deployed at: `2026-04-24`
- `SafeModuleSetup`: `0x54459A9431bD98c754180DEB32B067Cf31bDfF33`
- `ContractAllowlist`: `0x577be362178d20A3370722807d0294fA5D8A5a2A`
- `AgentRaiseFactory`: `0x45179eE92887e5770E42CD239644bc7b662673af`
- `USDM`: `0xFAfDdbb3FC7688494971a79cc65DCa3EF82079E7`
- `SafeProxyFactory`: `0xC22834581EbC8527d974F8a1c97E1bEA4EF910BC`
- `SafeSingleton`: `0xfb1bffC9d739B8D520DaF37dF666da4C687191EA`
- `SafeFallbackHandler`: `0x017062a1dE2FE6b99BE3d9d37841FeD19F573804`
- `ERC8004 IdentityRegistry`: `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432`
- `ERC8004 ReputationRegistry`: `0x8004BAa17C55a88189AE136b182e5fdA19dE9b63`

### Frontend Sources of Truth

- Testnet config: [frontend/config/deployment.testnet.json](/Users/lucatropea/Desktop/Backed/app/frontend/config/deployment.testnet.json:1)
- Mainnet config: [frontend/config/deployment.mainnet.json](/Users/lucatropea/Desktop/Backed/app/frontend/config/deployment.mainnet.json:1)
- Runtime selection: [frontend/lib/deployment.ts](/Users/lucatropea/Desktop/Backed/app/frontend/lib/deployment.ts:1)

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

### Mainnet factory stack

```bash
cd backend
NO_PROXY="*" forge script script/DeployNewAgentRaiseFactory.s.sol:DeployNewAgentRaiseFactory \
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
   - `frontend/config/deployment.testnet.json`
   - `frontend/config/deployment.mainnet.json`
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
