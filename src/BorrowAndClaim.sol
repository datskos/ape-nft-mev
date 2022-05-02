pragma solidity ^0.8.10;
pragma abicoder v2;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {ILendingPoolAddressesProvider, ILendingPool, IFlashLoanReceiver} from "./interfaces/aave.sol";
import {IRoyaltyFeeManager, IExecutionStrategy, ILooksRare, LooksRare} from "./interfaces/looksrare.sol";
import {IOtherDeed} from "./interfaces/ape.sol";

interface IWETH is IERC20 {
    function withdraw(uint256) external;
    function deposit(uint256) external payable;
}

// example long-tail MEV to buy a floor MAYC with an unclaimed otherdeed, claim the otherdeed and sell back the MAYC
// inspired by: https://twitter.com/davidiola_/status/1520688640132800513
// David's tx: https://etherscan.io/tx/0x62955836139fa34e8de69107b69e3f810373a188eb4d6d177f71d4bef7ae8f4d
contract BorrowAndClaim is IFlashLoanReceiver, Ownable {

    struct FlashLoanParams {
        uint256 feeCover; // should be >= (buyAmt - sellAmt) + exchange fees + aaveFee
        // for buy
        LooksRare.TakerOrder takerBid;
        LooksRare.MakerOrder makerAsk;
        // for sell
        LooksRare.TakerOrder takerAsk;
        LooksRare.MakerOrder makerBid;
    }

    IWETH public weth;
    ILendingPool public aaveLendingPool;
    ILooksRare public exchange;
    IOtherDeed public otherdeedContract;
    address public transferManager;

    constructor(address _weth, address _aaveAddressProvider, address _exchange, address _transferManager, address _otherDeedContract) {
        weth = IWETH(_weth);
        aaveLendingPool = ILendingPool(ILendingPoolAddressesProvider(_aaveAddressProvider).getLendingPool());
        exchange = ILooksRare(_exchange);
        otherdeedContract = IOtherDeed(_otherDeedContract);
        transferManager = _transferManager;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }

    receive() external payable {}

    function grab(
        LooksRare.TakerOrder calldata takerBid,
        LooksRare.MakerOrder calldata makerAsk,
        LooksRare.TakerOrder calldata takerAsk,
        LooksRare.MakerOrder calldata makerBid)
    external payable onlyOwner {
        // upfront sanity checks so we dont waste gas
        require(otherdeedContract.claimableActive(), "not claimable");
        require(!otherdeedContract.betaClaimed(takerBid.tokenId), "already claimed");
        require(msg.value > 0, "insufficient fee cover");
        require(takerBid.tokenId == takerAsk.tokenId, "tokens not consistent");
        require(makerBid.collection == makerAsk.collection, "collections not consistent");

        // (1) Take out loan
        FlashLoanParams memory flp = FlashLoanParams({
          feeCover: msg.value,
          takerBid: takerBid,
          makerAsk: makerAsk,
          takerAsk: takerAsk,
          makerBid: makerBid
        });
        address[] memory assets = new address[](1);
        assets[0] = address(weth);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = takerBid.price;
        aaveLendingPool.flashLoan(
            address(this),
            assets,
            amounts,
            new uint256[](1),
            address(this),
            abi.encode(flp),
            0
        );
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == address(aaveLendingPool), "not flash loan source");
        require(initiator == address(this), "can only be self-initiated");
        require(assets.length == 1 && assets[0] == address(weth), "wrong currency");
        require(amounts.length == 1 && premiums.length == 1, "single asset only");
        FlashLoanParams memory flp = abi.decode(params, (FlashLoanParams));
        require(weth.balanceOf(address(this)) >= flp.takerBid.price, "insufficient funds");

        // (2) Buy MAYC
        weth.approve(address(exchange), flp.takerBid.price);
        exchange.matchAskWithTakerBid(flp.takerBid, flp.makerAsk);

        // (3) Claim Otherdeed
        uint256[] memory betas = new uint256[](1);
        betas[0] = flp.takerBid.tokenId;
        otherdeedContract.nftOwnerClaimLand(new uint256[](0), betas);

        // (4) Sell back MAYC
        IERC721(flp.makerBid.collection).setApprovalForAll(transferManager, true);
        exchange.matchBidWithTakerAsk(flp.takerAsk, flp.makerBid);

        // (5) Pay back Loan
        weth.deposit{value: flp.feeCover}(flp.feeCover);
        weth.approve(address(aaveLendingPool), amounts[0] + premiums[0]);

        return true;
    }

    function calculateTotalExchangeFee(address strategy, address collection, uint256 tokenId, uint256 price) public view returns (uint256) {
        return _calculateProtocolFee(strategy, price) + _calculateRoyaltyFee(collection, tokenId, price);
    }

    function _calculateProtocolFee(address executionStrategy, uint256 amount) internal view returns (uint256) {
        uint256 protocolFee = IExecutionStrategy(executionStrategy).viewProtocolFee();
        return (protocolFee * amount) / 10000;
    }

    function _calculateRoyaltyFee(address collection, uint256 tokenId, uint256 amount) internal view returns (uint256) {
        IRoyaltyFeeManager rfm = IRoyaltyFeeManager(exchange.royaltyFeeManager());
        (address ra, uint256 rf) = rfm.calculateRoyaltyFeeAndGetRecipient(collection, tokenId, amount);
        if (ra == address(0)) {
            return 0;
        }
        return rf;
    }

}
