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
    // Chainlinnk VRF variables
    uint16 private constant _REQUEST_CONFIRMATIONS = 3;
    uint32 private constant _NUM_WORDS = 1;
    VRFCoordinatorV2Interface private immutable _VRF_COORDINATOR;
    bytes32 private immutable _GAS_LANE;
    uint64 private immutable _SUBSCRIPTION_ID;
    uint32 private immutable _CALLBACK_GAS_LIMIT; 

    // Number of NFTs in the collection
    uint256 public constant NUM_NFTS = 10;
    // Percentage of fees to be collected by the marketplace (10%)
    uint256 public constant FEE_PERCENTAGE = 10;
    // Percentage of price increase for the next NFT (10%)
    uint256 public constant PRICE_INCREMENT_PERCENTAGE = 10;
    // Number of NFTs sold between lottery calls
    uint256 public constant LOTTERY_TRIGGER_INTERVAL = 5;
    // Initial delay for the first lottery call
    uint256 public constant INITIAL_LOTTERY_DELAY = 90 days;
    // Delay for the second mandatory lottery call
    uint256 public constant SECOND_LOTTERY_DELAY = 130 days;
    // Delay for the third mandatory lottery call
    uint256 public constant THIRD_LOTTERY_DELAY = 170 days;
    // Maximum duration for the marketplace operation
    uint256 public constant MAX_MARKETPLACE_OPERATION_DAYS = 210 days;
    // Duration of the marketplace lock
    uint256 public constant LOCK_DURATION = 481 days;
    
    // This address will receive the fees. Also, is the initial owner of the NFTs.
    address payable public immutable ARTISTS;
    // Bubble NFT contract
    IBubbleNFT public immutable NFT_CONTRACT;   
    // Timestamp of the deployment
    uint256 public immutable DEPLOYMENT_TIMESTAMP;

    // ID of the NFT currently on sale
    uint256 public sellingNftId;
    // Number of NFTs sold
    uint256 public nftsSold;
    // Price of the current NFT on sale
    uint256 public currentPrice;
    // Flag to check if the first mandatory lottery has been done
    bool public firstMandatoryLotteryDone;
    // Flag to check if the second mandatory lottery has been done
    bool public secondMandatoryLotteryDone;
    // Timestamp of the lock
    uint256 public lockTimestamp;
    // Balance of the owners
    mapping(address => uint256) public balances;

    // Emitted when an NFT is purchased
    event NFTPurchased(address indexed buyer, uint256 indexed nftId, uint256 indexed price);
    // Emitted when a lottery call is requested
    event LotteryRequested(uint256 indexed requestId, uint256 indexed timestamp);
    // Emitted when the marketplace is locked
    event MarketplaceLocked(uint256 indexed timestamp);
    // Emitted when the NFTs are released
    event NFTsReleased(uint256 indexed timestamp);
    // Emitted when the random number is received
    event RandomWordsReceived(uint256 indexed randomWords);

    /**
     * @dev Constructor to set the NFT contract address, the fee recipient address and the Chainlink VRF variables.
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
        _VRF_COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        _GAS_LANE = gasLane;
        _SUBSCRIPTION_ID = subscriptionId;
        _CALLBACK_GAS_LIMIT = callbackGasLimit;

        NFT_CONTRACT = IBubbleNFT(nftAddress);
        ARTISTS = feeRecipientAddress;
        // Set the price for the first NFT
        currentPrice = initialPrice;
        DEPLOYMENT_TIMESTAMP = block.timestamp;
    }

    /**
     * @dev Function to purchase the current NFT in the sequential cycle.
     */
    function purchase() external payable whenNotPaused {        
        // Check if the buyer has sent enough funds to purchase the NFT and update the price
        require(msg.value >= currentPrice, "Insufficient funds to purchase NFT");

        // Calculate fees and owner value
        uint256 fees = (currentPrice * (FEE_PERCENTAGE*10**18)) / 10**20;
        uint256 ownerValue = currentPrice - fees;

        // Update the price for the next NFT (10% increase)
        currentPrice = currentPrice + (currentPrice * (PRICE_INCREMENT_PERCENTAGE*10**18)) / 10**20;

        // Get the ID of the NFT to be sold and increment the counter
        uint256 nftId = sellingNftId;
        sellingNftId = (sellingNftId+1) % (NUM_NFTS);

        // Increment the count of NFTs sold
        nftsSold++;        

        // Update the balance of the owner
        address nftOwner = NFT_CONTRACT.ownerOf(nftId);
        balances[nftOwner] += ownerValue;

        // Transfer fees to the designated address (ARTISTS)
        (bool success, ) = ARTISTS.call{value: fees}("");
        require(success, "Failed to send Ether");

        // Transfer the NFT to the buyer
        NFT_CONTRACT.approve(address(this), nftId); // The marketplace has privileges to make approvals and transfers during the regulated state
        NFT_CONTRACT.transferFrom(nftOwner, msg.sender, nftId);

        emit NFTPurchased(msg.sender, nftId, msg.value);

        // Check if it's time for a lottery call to potentially lock the marketplace
        if( (block.timestamp >= DEPLOYMENT_TIMESTAMP + INITIAL_LOTTERY_DELAY) && (nftsSold % LOTTERY_TRIGGER_INTERVAL == 0) ) {
            _performLottery();
        } 
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
     * @dev This function allows performing one lottery call to potentially lock the marketplace after the first mandatory lottery delay (130 days), another one after the second mandatory lottery delay (170 days) and eventually lock the marketplace after the maximum operation time has passed (210 days). 
     * @notice Can be called by anyone.
     */
    function tryLock() external whenNotPaused {
        if(!firstMandatoryLotteryDone && block.timestamp >= DEPLOYMENT_TIMESTAMP + SECOND_LOTTERY_DELAY){
            firstMandatoryLotteryDone = true;
            _performLottery();
        }else if(!secondMandatoryLotteryDone && block.timestamp >= DEPLOYMENT_TIMESTAMP + THIRD_LOTTERY_DELAY){
            secondMandatoryLotteryDone = true;
            _performLottery();
        }else if(block.timestamp >= DEPLOYMENT_TIMESTAMP + MAX_MARKETPLACE_OPERATION_DAYS){
            _pause();
            lockTimestamp = block.timestamp;
            emit MarketplaceLocked(lockTimestamp);
        }else{
            revert("Not the right time to lock the marketplace");
        }
    }

    /**
     * @dev Function to release the NFTs after the lockDuration has passed.
     * @notice Can be called by anyone.
     */
    function release() external whenPaused {
        require(block.timestamp >= lockTimestamp + LOCK_DURATION, "Lock duration not yet elapsed");

        // Release the restriction on the NFT contract
        NFT_CONTRACT.releaseRestriction();
        emit NFTsReleased(block.timestamp);
    }

    /**
     * @dev Function to get the available balance of an account.
     * @param account Address of the account.
     */
    function getBalance(address account) external view returns (uint256) {
        return balances[account];
    }

    /**
     * @dev Function to get the timestamp of the deployment. 
    */
    function getDeploymentTimestamp() external view returns (uint256) {
        return DEPLOYMENT_TIMESTAMP;
    }

    /**
     * @dev Function to perform the lottery call and potentially lock the marketplace.
     * @notice It performs a Chainlink VRF call to get a random number, which is returned in the fulfillRandomWords function called by the VRF Coordinator.
     */
    function _performLottery() internal {
        uint256 requestId = _VRF_COORDINATOR.requestRandomWords(
            _GAS_LANE, 
            _SUBSCRIPTION_ID,
            _REQUEST_CONFIRMATIONS,
            _CALLBACK_GAS_LIMIT,
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
        emit RandomWordsReceived(randomWords[0]);
        if(randomWords[0] % 10 == 0){
            _pause();
            lockTimestamp = block.timestamp;
            emit MarketplaceLocked(lockTimestamp);
        }
    }
}