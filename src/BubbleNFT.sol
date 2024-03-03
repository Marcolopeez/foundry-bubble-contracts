// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IBubbleNFT} from "./interfaces/IBubbleNFT.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title BubbleNFT
 * @author Marco López
 * @notice BubbleNFT implementation of ERC-721 Non-Fungible Token with additional features.
 */
contract BubbleNFT is IBubbleNFT, ERC721, AccessControl {
    ///@notice The deployer role ID for setting the marketplace address
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");
    ///@notice The Marketplace role ID for the AccessControl contract
    bytes32 public constant MARKET_ROLE = keccak256("MARKET_ROLE");

    ///@notice Indicates whether the NFT is in a regulated state
    bool public regulatedState;

    ///@notice Bool to check if the marketplace address has been set
    bool private _marketSet = false;

    mapping(uint256 tokenId => string) private _tokenURIs;

    /**
     * @dev Constructor to mint 10 NFTs to the deployer and initialize contract state.
     */
    constructor(string[10] memory tokenURIs) ERC721("BubbleNFT", "BLE") {
        _grantRole(DEPLOYER_ROLE, msg.sender); 

        // Mint 10 NFTs to the deployer
        for (uint256 i = 0; i < 10; i++) {
            _tokenURIs[i] = tokenURIs[i];
            _safeMint(msg.sender, i);
        }

        // Set the initial regulated state to true
        regulatedState = true;
    }

    /**
        @dev Sets the marketplace address
        @param marketAddress The address of the shop 
    */
    function setMarket(address marketAddress) external onlyRole(DEPLOYER_ROLE) {
        require(!_marketSet, "Market address already set");
        _marketSet = true;
        _grantRole(MARKET_ROLE, marketAddress);
    }

    /**
     * @dev Function to release the transfer restriction, can only be called by the marketplace.
     */
    function releaseRestriction() external onlyRole(MARKET_ROLE){
        require(regulatedState, "Bubble NFT is not in a regulated state");
        regulatedState = false;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return _tokenURIs[tokenId];
    }
    
    /**
     * @dev Approve `to` to operate on `tokenId`
     * @notice When the NFT is in the regulated state, only the marketplace can do an approval. Also, the marketplace is the only address that can be approved.
     *         When the NFT is not in the regulated state, the NFT works as a normal ERC721 token.
     * @param to The address to approve
     * @param tokenId The token ID to approve
     */
    function approve(address to, uint256 tokenId) public override(ERC721, IBubbleNFT){
        if(regulatedState) {
            require(hasRole(MARKET_ROLE, msg.sender), "Caller is not the marketplace");
            require(hasRole(MARKET_ROLE, to), "Marketplace is the only approvable address");
            _approve(to, tokenId, _requireOwned(tokenId));            
        }else{
            super.approve(to, tokenId);
        }
    }

    /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     * @notice When the NFT is in the regulated state, only the marketplace can be approved.
     *         When the NFT is not in the regulated state, the NFT works as a normal ERC721 token.
     * @param operator The address to approve
     * @param approved The token ID to approve
     */
    function setApprovalForAll(address operator, bool approved) public override(ERC721, IBubbleNFT){
        if(regulatedState) {
            revert("Set approval for all is not allowed in regulated state");       
        }
        super.setApprovalForAll(operator, approved); // @todo This call change the msg.sender?
    }

    /**
     * @dev Transfer `tokenId` from `from` to `to`
     * @notice When the NFT is in the regulated state, only the marketplace can perform a transferFrom.
     *         When the NFT is not in the regulated state, the NFT works as a normal ERC721 token.
     * @param from The current owner of the token
     * @param to The address to transfer the token to
     * @param tokenId The token ID to transfer
     */
    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IBubbleNFT){
        if(regulatedState) {
            require(hasRole(MARKET_ROLE, msg.sender), "Caller is not the marketplace");  
        }
        super.transferFrom(from, to, tokenId);    
    }

    /**  
     * @dev Safely transfer `tokenId` 
     * @notice It reverts if the NFT is in the regulated state.
     *         When the NFT is not in the regulated state, the NFT works as a normal ERC721 token.
     * @param from The current owner of the token
     * @param to The address to transfer the token to
     * @param tokenId The token ID to transfer
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override(ERC721, IBubbleNFT){
        if(regulatedState) {
            revert("Safe transfer is not allowed in regulated state");
        }else{
            super.safeTransferFrom(from, to, tokenId, data);
        }
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view override(ERC721, IBubbleNFT) returns (address) {
        return _requireOwned(tokenId);
    }

    /**
        @notice Returns the supported interfaces collection
        @param interfaceId The interface identifier
    */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return ERC721.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
    }
}