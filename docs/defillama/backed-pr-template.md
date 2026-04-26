## DefiLlama TVL PR

Repository: `DefiLlama/DefiLlama-Adapters`

Path to add:

`projects/backed/index.js`

Contents:

```js
const { sumTokens2 } = require('../helper/unwrapLPs')

const FACTORY = '0x45179eE92887e5770E42CD239644bc7b662673af'
const START = 1776985917
const PROJECT_ABI =
  'function getProject(uint256) view returns (uint256 agentId,string name,string description,string categories,address agent,address treasury,address sale,address agentExecutor,address collateral,uint8 operationalStatus,string statusNote,uint256 createdAt,uint256 updatedAt)'

async function tvl(api) {
  const projectCount = Number(
    await api.call({
      target: FACTORY,
      abi: 'uint256:projectCount',
    })
  )

  if (!projectCount) return {}

  const projectIds = Array.from({ length: projectCount }, (_, i) => i)
  const projects = await api.multiCall({
    target: FACTORY,
    calls: projectIds,
    abi: PROJECT_ABI,
  })

  const tokensAndOwners = projects.flatMap(({ collateral, sale, treasury }) => [
    [collateral, sale],
    [collateral, treasury],
  ])

  return sumTokens2({ api, tokensAndOwners })
}

module.exports = {
  methodology:
    'TVL is the sum of collateral tokens currently held by every Backed Sale contract and every project treasury Safe deployed by the AgentRaiseFactory on MegaETH.',
  start: START,
  megaeth: { tvl },
}
```

Test result:

```text
--- megaeth ---
Total: 0.00

--- tvl ---
Total: 0.00

------ TVL ------
megaeth                   0.00

total                    0.00
```

Why TVL is zero now:

- Mainnet factory `0x45179eE92887e5770E42CD239644bc7b662673af`
- `projectCount()` on MegaETH mainnet currently returns `0`
- the adapter is already future-proofed for all new raises created by the factory

Suggested PR body:

```md
##### Name (to be shown on DefiLlama):
Backed

##### Twitter Link:
https://x.com/BackedApp

##### List of audit links if any:
None yet

##### Website Link:
https://backed.app

##### Logo (High resolution, will be shown with rounded borders):
https://pbs.twimg.com/profile_images/2027116622847361024/fE1H-gWi_400x400.jpg

##### Current TVL:
0

##### Treasury Addresses (if the protocol has treasury):
Per-project Safe treasuries are deployed dynamically by the factory. TVL adapter reads them from the factory on-chain.

##### Chain:
MegaETH

##### Coingecko ID (so your TVL can appear on Coingecko, leave empty if not listed): (https://api.coingecko.com/api/v3/coins/list)

##### Coinmarketcap ID (so your TVL can appear on Coinmarketcap, leave empty if not listed): (https://api.coinmarketcap.com/data-api/v3/map/all?listing_status=active,inactive,untracked&start=1&limit=10000)

##### Short Description (to be shown on DefiLlama):
Backed lets users create and fund Autonomous Agent Organizations on MegaETH through on-chain raises and treasury-managed agent execution.

##### Token address and ticker if any:
No single protocol token. Each successful raise mints a project-specific AgentVaultToken.

##### Category (full list at https://defillama.com/categories) *Please choose only one:
Launchpad

##### Oracle Provider(s): Specify the oracle(s) used (e.g., Chainlink, Band, API3, TWAP, etc.):
None in TVL adapter

##### Implementation Details: Briefly describe how the oracle is integrated into your project:
TVL is computed directly from on-chain balances, no oracle dependency in the adapter.

##### Documentation/Proof: Provide links to documentation or any other resources that verify the oracle's usage:
https://backed.app

##### forkedFrom (Does your project originate from another project):
No

##### methodology (what is being counted as tvl, how is tvl being calculated):
TVL is the sum of collateral tokens currently held by every Sale contract and every project treasury Safe deployed by the AgentRaiseFactory on MegaETH.

##### Github org/user (Optional, if your code is open source, we can track activity):

##### Does this project have a referral program?
No
```

On-chain references:

- Factory: `0x45179eE92887e5770E42CD239644bc7b662673af`
- Chain: `MegaETH mainnet`
- RPC: `https://mainnet.megaeth.com/rpc`
