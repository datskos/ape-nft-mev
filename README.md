## NFT MEV

Implementation of a long-tail MEV strategy that buys a floor-priced MAYC with an unclaimed otherdeed, claims the otherdeed, and then sells back the MAYC.

Based on [davidiola_'s transaction](https://twitter.com/davidiola_/status/1520688640132800513). I don't think he ever released his code so this is my take on it.

### Details

In general, for this sort of strategy to be successful, the following should be true:

```
V = Value of item we obtain (in this case V = 15 ether for a MAYC otherdeed on May 1st)

M_buy = Lowest-priced MAYC with an unclaimed otherdeed
M_sell = Highest-priced collection offer (StrategyAnyItemFromCollectionForFixedPrice)
M_sellFee = LooksRare exchange fee for selling the MAYC
I = flash loan interest rate (for AAVE, currently set to 9 BPS)
Gf = Transaction fee or FlashBots bid

Total_Cost = (M_sell + M_sellFee + (M_buy * I) + Bf) - M_buy

If V > Total_Cost tx may be worth executing. (Not atomic MEV. V represents the value the NFT can be sold for)
```

This repo includes the smart contract that would execute the MEV.
However, you would need to separately listen to LooksRare orders to find
suitable `M_buy` and `M_sell` asks and bids, filter out those that have already
been claimed, and execute when the delta between the ask and bid is sufficiently small.
For the example in the test case (`src/test/BorrowAndClaim.t.sol`), the floor price
was 28E and the highest collection bid was 26.4E. So even though one would have to pay on the order of
2.8E for the ask/bid differential and all fees + gas, that is still much lower than
the MAYC land floor price as of the date of execution, making this profitable at the time.
Note that you should be able to find or calculate all values listed above off-chain before executing the transaction.

## Try it out

You can run this implementation against a historical block. You'll need access to an Ethereum archive node which you can get for free from alchemy or moralis.

```shell
forge test --fork-url <ARCHIVE_NODE_RPC> --fork-block-number 14690747
```

## Disclaimer

Not financial advice. No warranty or guarantee. Provided for illustration purposes only.
