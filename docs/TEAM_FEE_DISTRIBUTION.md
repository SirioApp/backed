# Team Fee Distribution

This note explains how the team fee works on-chain in the current contracts.

Relevant contract logic:

- [AgentVaultToken.sol](/Users/lucatropea/Desktop/Backed/app/backend/src/token/AgentVaultToken.sol:126)
- [Sale.sol](/Users/lucatropea/Desktop/Backed/app/backend/src/launch/Sale.sol:172)

## Short Answer

Yes: the current contract logic charges the team **5% of profit only**.

It is **not** taken:

- when users commit
- when the sale is finalized
- when users claim shares

It is taken only when `finalizeSettlement()` is called on the vault token.

At that moment:

1. the vault checks how much collateral has been returned
2. it compares that amount to the original accepted raise
3. if there is a profit, it sends **5% of that profit** to `PLATFORM_FEE_RECIPIENT`
4. the remaining assets stay in the vault for investors to redeem pro rata

## Where It Happens On-Chain

The fee is calculated here:

```solidity
uint256 grossAssets = _asset.balanceOf(address(this));
uint256 feeAmount;
if (grossAssets > initialAssets && PLATFORM_FEE_BPS > 0) {
    uint256 profit = grossAssets - initialAssets;
    feeAmount = (profit * PLATFORM_FEE_BPS) / BPS;
    if (feeAmount > 0) {
        _asset.safeTransfer(PLATFORM_FEE_RECIPIENT, feeAmount);
    }
}

settledAssets = grossAssets - feeAmount;
```

Meaning:

- `initialAssets` = how much capital was accepted at raise close
- `grossAssets` = how much collateral is inside the vault when settlement happens
- `profit` = `grossAssets - initialAssets`
- team fee = `5%` of `profit`

## Simple Example With Round Numbers

### Starting point

- Accepted raise: `1,000`
- Team fee: `5% of profit`
- Investor A owns `600` shares
- Investor B owns `400` shares

### During the raise

The sale closes and accepts `1,000`.

At this point:

- the treasury receives `1,000`
- investors receive shares
- the team receives `0`

## Settlement example

Later, the treasury sends back `1,200` to the vault and calls `finalizeSettlement()`.

So:

- original capital = `1,000`
- returned amount = `1,200`
- profit = `200`

### Team fee

`5%` of `200` = `10`

So the contract sends:

- `10` to the team fee recipient

And keeps:

- `1,190` inside the vault for investors

## Investor distribution

After the fee is paid, investors redeem from the net pool of `1,190`.

Investor A owns `60%` of shares:

- receives `714`

Investor B owns `40%` of shares:

- receives `476`

Check:

- team = `10`
- investor A = `714`
- investor B = `476`
- total = `1,200`

Everything matches.

## When The Team Gets Paid

The team gets paid exactly when `finalizeSettlement()` executes successfully.

So the sequence is:

1. sale closes
2. treasury operates during the term
3. treasury sends collateral back to the vault
4. `finalizeSettlement()` is called
5. team fee is transferred immediately
6. investors redeem the remaining assets

## Important Edge Cases

### If there is no profit

Example:

- accepted raise = `1,000`
- returned to vault = `1,000`

Profit = `0`

Result:

- team fee = `0`
- investors redeem `1,000`

### If there is a loss

Example:

- accepted raise = `1,000`
- returned to vault = `900`

Profit is not positive.

Result:

- team fee = `0`
- investors redeem `900`

So the team fee is **only on upside**, never on break-even or loss.

## Contract-Level Conclusion

The current fee mechanism works like this:

- fee base = **profit only**
- fee rate = **5%**
- payment timing = **at settlement finalization**
- recipient = `PLATFORM_FEE_RECIPIENT`
- investor redemption base = **net assets after fee**

## Test Added

I added a dedicated contract test with round numbers that proves this exact flow:

- accepted capital = `1,000`
- returned collateral = `1,200`
- team fee = `10`
- investor payouts = `714` and `476`

Test file:

- [AgentVaultToken.t.sol](/Users/lucatropea/Desktop/Backed/app/backend/test/token/AgentVaultToken.t.sol:166)
