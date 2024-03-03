// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IBubbleNFT
 * @author Marco López
 * @notice BubbleNFT interface of ERC-721 Non-Fungible Token with additional features.
 */
interface IBubbleNFT {
    /**
     * @dev Function to release the transfer restriction, can only be called by the marketplace.
     */
    function releaseRestriction() external;

    /**
     * @notice 
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @notice 
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @notice 
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @notice 
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) external;
    
    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);
}