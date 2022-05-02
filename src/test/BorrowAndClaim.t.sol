// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "ds-test/test.sol";
import "../BorrowAndClaim.sol";

interface Vm {
    function warp(uint256) external;
}

contract BorrowAndClaimTest is DSTest {
    BorrowAndClaim lc;
    Vm vm;

    function setUp() public {
        vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        lc = new BorrowAndClaim(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // weth
            0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5, // aave address provider,
            0x59728544B08AB483533076417FbBB2fD0B17CE3a, // looksrare exchange
            0xf42aa99F011A1fA7CDA90E5E98b277E306BcA83e, // transfer manager
            0x34d85c9CDeB23FA97cb08333b511ac86E1C4E258 // otherdeed
        );
    }

    // in a production set up you would get these params from the LooksRare API. you better be fast
    function _getBuyParams() internal view returns (LooksRare.TakerOrder memory, LooksRare.MakerOrder memory) {
        uint256 price = 28 ether;
        uint256 tokenId = 4107;
        uint256 minPct = 8500;

        LooksRare.TakerOrder memory takerBid = LooksRare.TakerOrder({
          isOrderAsk: false,
          taker: address(lc),
          price: price,
          tokenId: tokenId,
          minPercentageToAsk: minPct,
          params: ""
        });

        LooksRare.MakerOrder memory makerAsk = LooksRare.MakerOrder({
          isOrderAsk: true,
          signer: 0x6F7A49Da0F184509814039956137dadb9ccda4f8,
          collection: 0x60E4d786628Fea6478F785A6d7e704777c86a7c6,
          price: price,
          tokenId: tokenId,
          amount: 1,
          strategy: 0x56244Bb70CbD3EA9Dc8007399F61dFC065190031,
          currency: address(lc.weth()),
          nonce: 6,
          startTime: 0x626e3b1c,
          endTime: 0x6295c79f,
          minPercentageToAsk: 0x2134,
          params: "",
          v: 27,
          r: 0xb4886be36fb337325ba7c6d8b608c42e064d7ece227fa13a7a49e83399b7c559,
          s: 0x355954e101ea5bdc0b78aca1b6748ce5bd8c565603a0e2e81506f4cf62dfe921
        });

        return (takerBid, makerAsk);
    }

    function _getSellParams() internal view returns (LooksRare.TakerOrder memory, LooksRare.MakerOrder memory) {
        uint256 price = 0x16e5fa42076500000;
        uint256 tokenId = 4107;
        uint256 minPct = 8500;

        LooksRare.TakerOrder memory takerAsk = LooksRare.TakerOrder({
          isOrderAsk: true,
          taker: address(lc),
          price: price,
          tokenId: tokenId,
          minPercentageToAsk: minPct,
          params: ""
        });

        LooksRare.MakerOrder memory makerBid = LooksRare.MakerOrder({
          isOrderAsk: false,
          signer: 0x85Bc76AaF14aC2112BF87BF8F28a73c526B86Ba2,
          collection: 0x60E4d786628Fea6478F785A6d7e704777c86a7c6,
          price: 0x16e5fa42076500000,
          tokenId: 0, // any
          amount: 1,
          strategy: 0x86F909F70813CdB1Bc733f4D97Dc6b03B8e7E8F3, // "any item from collection strategy"
          currency: address(lc.weth()),
          nonce: 148,
          startTime: 0x626e3b0f,
          endTime: 0x626e488c,
          minPercentageToAsk: minPct,
          params: "",
          v: 27,
          r: 0x48b2f93af965922ddae50c6dcaadc22c217fe9be5b283e9bc894a85290633fab,
          s: 0x1b7b7401e737f99a4390c7f8f5dc98d70cddf5d96162d3e3b1a842d67b44db65
        });

        return (takerAsk, makerBid);
    }

    function testClaim() public {
        assertEq(IERC721(address(lc.otherdeedContract())).balanceOf(address(lc)), 0);

        (LooksRare.TakerOrder memory takerBid, LooksRare.MakerOrder memory makerAsk) = _getBuyParams();
        (LooksRare.TakerOrder memory takerAsk, LooksRare.MakerOrder memory makerBid) = _getSellParams();

        uint256 exchangeFee = lc.calculateTotalExchangeFee(makerBid.strategy, makerBid.collection, 4107, takerAsk.price);
        uint256 lendingFee = takerBid.price * 9 / 10000;
        uint256 spread = takerBid.price - takerAsk.price;
        uint256 totalFee = exchangeFee + lendingFee + spread;
        assertEq(totalFee, 2813200000000000000);

        vm.warp(makerAsk.startTime);
        lc.grab{value: 2 * totalFee}(takerBid, makerAsk, takerAsk, makerBid);
        assertEq(IERC721(address(lc.otherdeedContract())).balanceOf(address(lc)), 1); // got it
    }


}
