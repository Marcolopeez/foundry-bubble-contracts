// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBubble_NFT} from "./interfaces/IBubble_NFT.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Bubble_Marketplace
 * @author Marco
 * @notice Bubble_Marketplace implementation for selling Bubble_NFTs in a sequential cycle.
 */
contract AdvancedMarketplace is Pausable {

    // Number of NFTs in the collection
    uint256 public constant NUM_NFTS = 10;
    // Percentage of fees to be collected by the marketplace (20%)
    uint256 public constant FEE_PERCENTAGE = 20;
    // Duration of the marketplace lock (1 month)
    uint256 public constant LOCK_DURATION = 30 days;
    // Threshold for triggering the marketplace lock (to be set based on Chainlink Oracle response)
    uint256 public constant LOCK_THRESHOLD = 0;

    // Bubble NFT contract
    IBubble_NFT public nftContract;    
    // ID of the NFT currently on sale
    uint256 public sellingNftId = 0;
    // Number of NFTs sold
    uint256 public nftsSold;
    // Price of the last NFT
    uint256 public lastPrice = 0.0909 ether;
    // Timestamp of the last lottery call
    uint256 public lastLotteryTimestamp;
    // Timestamp of the lock
    uint256 public lockTimestamp;
    // Address of the marketplace fee recipient
    address payable public immutable feeRecipient;
    

    /**
     * @dev Constructor to set the NFT contract address.
     * @param nftAddress Address of the NFT contract.
     * @param feeRecipientAddress Address of the fee recipient.
     */
    constructor(address nftAddress, address payable feeRecipientAddress) {
        nftContract = IBubble_NFT(nftAddress);
        feeRecipient = feeRecipientAddress;
        // Set the initial timestamp of the lottery call to the contract deployment time
        lastLotteryTimestamp = block.timestamp;
    }

    /**
     * @dev Function to purchase the current NFT in the sequential cycle.
     */
    function purchaseNFT() external payable whenNotPaused {
        uint256 nftId = sellingNftId;
        sellingNftId = (sellingNftId + 1) % NUM_NFTS;
        
        // Calculate the current price based on the incremental pricing strategy
        lastPrice = (lastPrice * 110) / 100;

        require(msg.value >= lastPrice, "Insufficient funds to purchase NFT");

        // Calculate fees and remaining value for the owner
        uint256 fees = (lastPrice * FEE_PERCENTAGE) / 100;
        uint256 ownerValue = lastPrice - fees;

        // Transfer fees to the designated address
        require(address(this).balance >= fees, "Insufficient funds to pay fees");
        feeRecipient.transfer(fees);

        // Transfer value to the NFT owner
        require(address(this).balance >= ownerValue, "Insufficient funds to pay fees");
        address payable nftOwner = payable(nftContract.ownerOf(nftId));
        nftOwner.transfer(ownerValue);

        // Transfer remaining value to the NFT owner
        nftContract.approve(address(this), nftId); // The marketplace has privileges to make approvals and transfers during the regulated state
        nftContract.safeTransferFrom(nftOwner, msg.sender, nftId, "");

        // Increment the count of sold NFTs in the cycle
        nftsSold++;

        // Check if it's time for a lottery call to potentially lock the marketplace
        if (nftsSold % 4 == 0 || block.timestamp - lastLotteryTimestamp > 20 days) {
            lastLotteryTimestamp = block.timestamp;
            _performLottery();
        }
    }

    /**
     * @dev Function to release the marketplace lock after the lockDuration has passed.
     * Can be called by anyone.
     */
    function releaseMarketplaceLock() external whenPaused {
        require(block.timestamp - lockTimestamp > LOCK_DURATION, "Lock duration not yet elapsed");

        // Release the restriction on the NFT contract
        nftContract.releaseRestriction();
    }

    /**
     * @dev Function to perform the lottery call and potentially lock the marketplace.
     * (Implementation of this function requires interaction with a Chainlink Oracle, not included yet).
     */
    function _performLottery() internal {
        // Implementation of the lottery call to obtain the result and set lockThreshold
        // (To be implemented using Chainlink Oracle)
        // If the result surpasses the threshold, pause the marketplace for lockDuration
        if (LOCK_THRESHOLD == 0) {
            lockTimestamp = block.timestamp;
            _pause();
        }
    }
}