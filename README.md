## NFT MEV

Implementation of a long-tail MEV strategy that buys a floor-priced MAYC with an unclaimed otherdeed, claims the otherdeed, and then sells back the MAYC.

Based on [davidiola_'s transaction](https://twitter.com/davidiola_/status/1520688640132800513). I don't think he ever released his code so this is my take on it.

## Try it out

You can run this implementation against a historical block. You'll need access to an Ethereum archive node which you can get for free from alchemy or moralis.

```shell
forge test --fork-url <ARCHIVE_NODE_RPC> --fork-block-number 14690747
```
