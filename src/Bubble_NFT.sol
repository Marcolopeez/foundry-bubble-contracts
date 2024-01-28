// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IBubble_NFT} from "./interfaces/IBubble_NFT.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Bubble_NFT
 * @author Marco
 * @notice Bubble_NFT implementation of ERC-721 Non-Fungible Token with additional features.
 */
contract Bubble_NFT is IBubble_NFT, ERC721, AccessControl {
    ///@notice The admin role ID for setting the marketplace address
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    ///@notice The Marketplace role ID for the AccessControl contract
    bytes32 public constant MARKET_ROLE = keccak256("MARKET_ROLE");

    // Address of the marketplace that can control transfers when regulatedState is true
    address public marketplace;
    // Indicates whether the NFT is in a regulated state
    bool public regulatedState;

    ///@notice Bool to check if the marketplace address has been set
    bool private _marketSet = false;

    /**
     * @dev Constructor to mint 10 NFTs to the deployer and initialize contract state.
     */
    constructor() ERC721("Bubble_NFT", "BLE") {
        _grantRole(ADMIN_ROLE, msg.sender); //Revisar que implica el rol de Admin en el contrato AccessControl.sol

        // Mint 10 NFTs to the deployer
        for (uint256 i = 0; i < 10; i++) {
            //todo: update with the actual metadata URI of the IPFS
            _safeMint(msg.sender, i);
        }

        // Set the initial regulated state to true
        regulatedState = true;
    }

    /**
        @notice Sets the marketplace address
        @param marketAddress The address of the shop 
    */
    function setMarket(address marketAddress) external onlyRole(ADMIN_ROLE) {
        require(!_marketSet, "Market address already set");
        _marketSet = true;
        _grantRole(MARKET_ROLE, marketAddress);
    }

    /**
     * @dev Function to release the transfer restriction, can only be called by the marketplace.
     */
    function releaseRestriction() external {
        require(regulatedState, "Bubble NFT is not in a regulated state");
        require(hasRole(MARKET_ROLE, msg.sender), "Caller is not the marketplace");
        regulatedState = false;
    }
    
    /**
     * @notice 
     */
    function approve(address to, uint256 tokenId) public virtual override(ERC721, IBubble_NFT){
        if(regulatedState) {
            require(hasRole(MARKET_ROLE, msg.sender), "Caller is not the marketplace");
            _approve(to, tokenId, _requireOwned(tokenId));            
        }else{
            _approve(to, tokenId, _msgSender());
        }
    }

    /**
     * @notice 
     */
    function setApprovalForAll(address operator, bool approved) public virtual override(ERC721, IBubble_NFT){
        if(regulatedState) {
            require(hasRole(MARKET_ROLE, msg.sender), "Caller is not the marketplace");
            require(hasRole(MARKET_ROLE, operator), "Marketplace is the only approvebable address");
            require(approved, "Marketplace cannot be unapproved");         
        }
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @notice 
     */
    function transferFrom(address from, address to, uint256 tokenId) public virtual override(ERC721, IBubble_NFT){
        if(regulatedState) {
            require(hasRole(MARKET_ROLE, msg.sender), "Caller is not the marketplace");  
        }
        
        if (to == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }
        // Setting an "auth" arguments enables the `_isAuthorized` check which verifies that the token exists
        // (from != 0). Therefore, it is not needed to verify that the return value is not 0 here.
        // If the auth value passed is non 0, then this function will check that `auth` is either the owner of the token, or approved to operate on the token (by the owner).
        address previousOwner = _update(to, tokenId, _msgSender());
        if (previousOwner != from) {
            revert ERC721IncorrectOwner(from, tokenId, previousOwner);
        }        
    }

    /**
     * @notice 
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual override(ERC721, IBubble_NFT){
        if(regulatedState) {
            require(hasRole(MARKET_ROLE, msg.sender), "Caller is not the marketplace");            
        }else{
            transferFrom(from, to, tokenId);
        }
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual override(ERC721, IBubble_NFT) returns (address) {
        return _requireOwned(tokenId);
    }

    /**
        @notice Returns the supported interfaces collection
        @param interfaceId The interface identifier
    */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return ERC721.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
    }
}