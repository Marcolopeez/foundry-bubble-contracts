// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IBubbleNFT} from "./interfaces/IBubbleNFT.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol"; 
import {VRFConsumerBaseV2} from "@chainlink/contracts/v0.8/vrf/VRFConsumerBaseV2.sol";

/**
 * @title BubbleMarketplace
 * @author Marco López
 * @notice BubbleMarketplace implementation for selling BubbleNFTs in a sequential cycle.
 */
contract BubbleMarketplace is Pausable, VRFConsumerBaseV2 {

    // Number of NFTs in the collection
    uint256 public constant NUM_NFTS = 10;
    // Percentage of fees to be collected by the marketplace (20%)
    uint256 public constant FEE_PERCENTAGE = 20;
    // Percentage of price increase for the next NFT (10%)
    uint256 public constant INCREMENT_PERCENTAGE = 10;
    // Duration of the marketplace lock (1 month)
    uint256 public constant LOCK_DURATION = 30 days;
    
    // Address of the marketplace fee recipient
    address payable public immutable FEE_RECIPIENT;
    // Bubble NFT contract
    IBubbleNFT public immutable NFT_CONTRACT;   

    // ID of the NFT currently on sale
    uint256 public sellingNftId = 0;
    // Number of NFTs sold
    uint256 public nftsSold;
    // Price of the current NFT on sale
    uint256 public currentPrice;
    // Timestamp of the last lottery call
    uint256 public lastLotteryTimestamp;
    // Timestamp of the lock
    uint256 public lockTimestamp;
    // Balance of the owners
    mapping(address => uint256) public balances;


    // Chainlinnk VRF variables
    uint16 private constant _REQUEST_CONFIRMATIONS = 3;
    uint32 private constant _NUM_WORDS = 1;
    VRFCoordinatorV2Interface private immutable _vrfCoordinator;
    bytes32 private immutable _gasLane;
    uint64 private immutable _subscriptionId;
    uint32 private immutable _callbackGasLimit;

    event NFTPurchased(address indexed buyer, uint256 indexed nftId, uint256 indexed price);
    event LotteryRequested(uint256 indexed requestId, uint256 indexed timestamp);
    event MarketplaceLocked(uint256 indexed timestamp);
    event MarketplaceNotLocked(uint256 indexed timestamp);
    event NFTsReleased(uint256 indexed timestamp);

    /**
     * @dev Constructor to set the NFT contract address and the fee recipient address.
     * @param nftAddress Address of the NFT contract.
     * @param feeRecipientAddress Address of the fee recipient.
     * @param initialPrice Price for the first NFT.
     * @param vrfCoordinator Address of the Chainlink VRF Coordinator.
     * @param gasLane The gas lane for the VRF Coordinator.
     * @param subscriptionId The subscription ID for the VRF Coordinator.
     * @param callbackGasLimit The gas limit for the VRF Coordinator callback.
     */
    constructor(
        address nftAddress, 
        address payable feeRecipientAddress, 
        uint256 initialPrice,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        _vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        _gasLane = gasLane;
        _subscriptionId = subscriptionId;
        _callbackGasLimit = callbackGasLimit;

        NFT_CONTRACT = IBubbleNFT(nftAddress);
        FEE_RECIPIENT = feeRecipientAddress;
        // Set the timestamp of the last lottery call to the contract deployment time
        lastLotteryTimestamp = block.timestamp;
        // Set the price for the first NFT
        currentPrice = initialPrice;
    }

    /**
     * @dev Function to purchase the current NFT in the sequential cycle.
     */
    function purchase() external payable whenNotPaused {        
        // Check if the buyer has sent enough funds to purchase the NFT and update the price
        require(msg.value >= currentPrice, "Insufficient funds to purchase NFT"); //@todo if + error pattern and add event for catch in front

        // Calculate fees and remaining value for the owner
        uint256 fees = (currentPrice * (FEE_PERCENTAGE*10**18)) / 10**20;
        uint256 ownerValue = currentPrice - fees;

        // Update the price for the next NFT (10% increase)
        currentPrice = currentPrice + (currentPrice * (INCREMENT_PERCENTAGE*10**18)) / 10**20;

        // Get the ID of the NFT to be sold and increment the counter
        uint256 nftId = sellingNftId;
        sellingNftId = (sellingNftId+1) % (NUM_NFTS);

        // Increment the count of sold NFTs
        nftsSold++;        

        // Update the balance of the owner
        address nftOwner = NFT_CONTRACT.ownerOf(nftId);
        balances[nftOwner] += ownerValue;

        // Transfer fees to the designated address
        require(address(this).balance >= fees, "Insufficient funds to pay fees");
        (bool success1, ) = FEE_RECIPIENT.call{value: fees}("");
        require(success1, "Failed to send Ether");

        // Transfer the NFT to the buyer
        NFT_CONTRACT.approve(address(this), nftId); // The marketplace has privileges to make approvals and transfers during the regulated state
        NFT_CONTRACT.transferFrom(nftOwner, msg.sender, nftId);

        emit NFTPurchased(msg.sender, nftId, msg.value);

        // Check if it's time for a lottery call to potentially lock the marketplace
        if (nftsSold % 5 == 0 || block.timestamp - lastLotteryTimestamp > 20 days) {
            _performLottery();
        }
    }

    /**
     * @dev Function to release the NFTs after the lockDuration has passed.
     * @notice Can be called by anyone.
     */
    function release() external whenPaused {
        require(block.timestamp - lockTimestamp > LOCK_DURATION, "Lock duration not yet elapsed");

        // Release the restriction on the NFT contract
        NFT_CONTRACT.releaseRestriction();
        emit NFTsReleased(block.timestamp);
    }

    /** 
     * @dev Function to withdraw the balance of the owner.
    */
    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "Insufficient balance");
        balances[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Failed to send Ether");
    }

    /**
     * @dev Function to get the available balance of an account.
     * @param account Address of the account.
     */
    function getBalance(address account) external view returns (uint256) {
        return balances[account];
    }

    /**
     * @dev Function to perform the lottery call and potentially lock the marketplace.
     * @notice It performs a Chainlink VRF call to get a random number, which is returned in the fulfillRandomWords function called by the VRF Coordinator.
     */
    function _performLottery() internal {
        lastLotteryTimestamp = block.timestamp;

        uint256 requestId = _vrfCoordinator.requestRandomWords(
            _gasLane, 
            _subscriptionId,
            _REQUEST_CONFIRMATIONS,
            _callbackGasLimit,
            _NUM_WORDS
        );
        
        emit LotteryRequested(requestId, block.timestamp);
    }

    /**
     * @dev This function is called by the VRF Coordinator to return the random number generated
     * @notice This function pauses the marketplace with a probability of 10%. 
     * @param randomWords The random number returned by the VRF Coordinator.
     */
    function fulfillRandomWords(uint256 /*requestId*/, uint256[] memory randomWords) internal override {        
        if(randomWords[0] % 10 == 0){
            _pause();
            lockTimestamp = block.timestamp;
            emit MarketplaceLocked(lockTimestamp);
        }
    }
}