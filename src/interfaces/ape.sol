pragma solidity ^0.8.10;

interface IOtherDeed {
    function betaClaimed(uint256 tokenId) external view returns (bool);
    function claimableActive() external view returns (bool);
    function nftOwnerClaimLand(uint256[] calldata alphaTokenIds, uint256[] calldata betaTokenIds) external;
}
