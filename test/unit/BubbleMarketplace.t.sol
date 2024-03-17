// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "@forge-std/Test.sol";
import {console} from "lib/forge-std/src/Script.sol";
import {Vm} from "@forge-std/Vm.sol";
import {BubbleNFT} from "../../src/BubbleNFT.sol";
import {BubbleMarketplace} from "../../src/BubbleMarketplace.sol";
import {DeployContracts} from "../../script/DeployContracts.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "../mocks/VRFCoordinatorV2Mock.sol";


contract BubbleMarketplace_Test is Test{
    BubbleNFT public nftContract;
    BubbleMarketplace public marketContract;
    HelperConfig public helperConfig;

    //uint64 subscriptionId;
    //bytes32 gasLane;
    //uint256 automationUpdateInterval;
    //uint32 callbackGasLimit;
    address public vrfCoordinatorV2;

    address public constant USER1 = address(0x1);
    address public constant USER2 = address(0x2);
    address public constant ANVIL_DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public constant SEPOLIA_DEPLOYER = 0x97aa42A297049DD6078B97d4C1f9d384B52f5905;
    address public constant FEE_RECIPIENT = address(0x4);
    
    address public DEPLOYER;

   
    /************************************** Modifiers **************************************/
    
    modifier purchaseNFTs(uint256 amount) {
        uint256 lastPrice = 0.1 ether;
        
        for(uint256 i = 0; i < amount; i++){
            vm.prank(USER1);
            marketContract.purchase{value: lastPrice}();
            lastPrice = (lastPrice*110)/100;
        }
        _;        
    }

    modifier purchase5NFTsAndFullfillWithSelectedWords() {
        uint256[] memory notRandomWords = new uint256[](1);
        notRandomWords[0] = uint256(10);

        uint256 lastPrice = 0.1 ether;
        
        for(uint256 i = 0; i < 5; i++){
            vm.prank(USER1);
            marketContract.purchase{value: lastPrice}();
            lastPrice = (lastPrice*110)/100;
        }

        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWordsWithOverride(
            uint256(1),
            address(marketContract),
            notRandomWords
        ); 
        _;
    }

    modifier onlyAnvil() { 
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    /************************************** Set Up **************************************/

    function setUp() public {
        vm.deal(USER1, 10 ether);
        vm.deal(USER2, 10 ether);
        DeployContracts deployer = new DeployContracts();
        (marketContract, nftContract, helperConfig) = deployer.run();
        (
            ,
            ,
            ,
            vrfCoordinatorV2,
            ,

        ) = helperConfig.activeNetworkConfig();
        if(block.chainid == 11155111){
            DEPLOYER = SEPOLIA_DEPLOYER;
        }else if(block.chainid == 31337){
            DEPLOYER = ANVIL_DEPLOYER;
        }
    }

    /************************************** Tests **************************************/

    function test_setUp() public {
        // Check the initial state of the marketplace contract
        assertEq(address(marketContract.NFT_CONTRACT()), address(nftContract), "Incorrect nft contract");
        assertEq(marketContract.lastLotteryTimestamp(), block.timestamp, "Incorrect last lottery stamp - It should be equal to the deployment time");
        assertEq(marketContract.FEE_RECIPIENT(), FEE_RECIPIENT, "Incorrect fee recipient");
        assertEq(marketContract.NUM_NFTS(), 10, "Incorrect number of nfts");
        assertEq(marketContract.FEE_PERCENTAGE(), 20, "Incorrect fee percentage");
        assertEq(marketContract.LOCK_DURATION(), 30 days, "Incorrect lock duration");
        for(uint256 i = 0; i < 10; i++){
            assertEq(nftContract.ownerOf(i), DEPLOYER, "Incorrect owner of the NFT");
        }
    }

    function test_purchase() public { 
        // Check the state before the purchase  
        assertEq(marketContract.currentPrice(), 0.1 ether, "Incorrect price");
        assertEq(marketContract.nftsSold(), 0, "Incorrect nfts sold");
        assertEq(marketContract.sellingNftId(), 0, "Incorrect selling nft id");

        // Obtain the initial balances of the fee recipient and the NFT owner
        uint256 feeRecipientPreviousBalance = FEE_RECIPIENT.balance;
        address owner = nftContract.ownerOf(0);
        uint256 ownerPreviousBalance = owner.balance;
        uint256 ownerPreviousBalanceInContract = marketContract.getBalance(owner);

        // Purchase the NFT
        vm.prank(USER1);
        marketContract.purchase{value: 0.1 ether}();

        // Check the state after the purchase
        assertEq(marketContract.currentPrice(), 0.11 ether, "Incorrect price");
        assertEq(marketContract.nftsSold(), 1, "Incorrect nfts sold");
        assertEq(marketContract.sellingNftId(), 1, "Incorrect selling nft id");
        assertEq(FEE_RECIPIENT.balance, feeRecipientPreviousBalance + 0.02 ether, "Incorrect fee recipient balance");
        assertEq(owner.balance, ownerPreviousBalance, "Incorrect owner balance");
        assertEq(marketContract.getBalance(owner), ownerPreviousBalanceInContract + 0.08 ether, "Incorrect owner balance in contract");
        assertEq(nftContract.ownerOf(0), USER1, "Incorrect new owner of the NFT");     
    }

    /**
     * @dev Function to test the purchase of 35 NFTs.
     */
    function test_purchase_35() public {
        uint256 lastPrice = 0.1 ether;
        Vm.Log[] memory entries;
        uint256 lastRequestId;
        vm.recordLogs();
        
        // Purchase 35 NFTs
        for(uint256 purchaseCount = 0; purchaseCount <= 35; purchaseCount++){
            // Obtain the balances of the fee recipient and the NFT owner
            uint256 feeRecipientPreviousBalance = FEE_RECIPIENT.balance;
            address owner = nftContract.ownerOf((purchaseCount)%10);
            uint256 ownerPreviousBalance = owner.balance;
            uint256 ownerPreviousBalanceInContract = marketContract.getBalance(owner);

            // Purchase a NF3
            vm.deal(address(0x15), address(0x15).balance + lastPrice);
            vm.prank(address(0x15));
            marketContract.purchase{value: lastPrice}();
            if((purchaseCount+1) % 5 == 0){     
                // Chainlink requestRandomWords           
                entries = vm.getRecordedLogs();
                // Check the requestId retuned by the requestRandomWords function
                assertTrue((uint256(entries[16].topics[1]) > 0) && (uint256(entries[16].topics[1]) != lastRequestId), "Incorrect requestId");
                lastRequestId = uint256(entries[16].topics[1]);

                assertEq(marketContract.lastLotteryTimestamp(), block.timestamp, "Incorrect last lottery stamp");
            }
            
            // Check the state after each purchase
            assertEq(marketContract.currentPrice(), (lastPrice*110)/100, "Incorrect price");
            assertEq(marketContract.nftsSold(), purchaseCount+1, "Incorrect nfts sold");
            assertEq(marketContract.sellingNftId(), (purchaseCount+1)%10, "Incorrect selling nft id");
            assertEq(FEE_RECIPIENT.balance, feeRecipientPreviousBalance + (lastPrice*20)/100, "Incorrect fee recipient balance");
            assertEq(owner.balance, ownerPreviousBalance, "Incorrect owner balance");
            assertEq(marketContract.getBalance(owner), ownerPreviousBalanceInContract + (lastPrice - ((lastPrice*20)/100)), "Incorrect owner balance in contract");
            assertEq(nftContract.ownerOf((purchaseCount)%10), address(0x15), "Incorrect new owner of the NFT");
            lastPrice = (lastPrice*110)/100;  
        }                                 
                       
    }

    function test_purchase_RevertIf_NotEnoughValue() public {
        // Purchase the NFT with insufficient funds
        vm.prank(USER1);
        vm.expectRevert(bytes("Insufficient funds to purchase NFT"));
        marketContract.purchase{value: 0.09 ether}();
    }

    function test_purchase_RevertIf_MarketIsPaused() public onlyAnvil() purchase5NFTsAndFullfillWithSelectedWords() {
        vm.prank(USER1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));   
        marketContract.purchase{value: 0.161051 ether}();        
    }

    function test_release() public onlyAnvil() purchase5NFTsAndFullfillWithSelectedWords() {
        assertTrue(nftContract.regulatedState(), "Incorrect NFT regulated state");
        vm.warp(block.timestamp + marketContract.LOCK_DURATION() + 1);
        marketContract.release();
        assertFalse(nftContract.regulatedState(), "Incorrect NFT regulated state");
    }

    function test_release_RevertIf_LockDurationNotElapsed() onlyAnvil() public purchase5NFTsAndFullfillWithSelectedWords() {
        vm.expectRevert(bytes("Lock duration not yet elapsed"));
        marketContract.release();
    }

    function test_release_RevertIf_MarketIsNotPaused() public {
        vm.expectRevert(abi.encodeWithSignature("ExpectedPause()"));        
        marketContract.release();
    }

    function test_withdraw() public purchaseNFTs(1){
        // Check the state before the withdrawal
        assertEq(marketContract.getBalance(DEPLOYER), 0.08 ether, "Incorrect balance");
        
        uint256 ownerPreviousBalance = DEPLOYER.balance;
        
        // Withdraw the balance
        vm.prank(DEPLOYER);
        marketContract.withdraw();
        
        // Check the state after the withdrawal
        assertEq(marketContract.getBalance(DEPLOYER), 0, "Incorrect balance");
        assertEq(DEPLOYER.balance, ownerPreviousBalance + 0.08 ether, "Incorrect balance");
    }

    function test_withdraw_RevertIf_InsufficientBalance() public {
        // Check the state before the withdrawal
        assertEq(marketContract.getBalance(DEPLOYER), 0, "Incorrect balance");
        
        // Withdraw the balance
        vm.prank(DEPLOYER);
        vm.expectRevert(bytes("Insufficient balance"));
        marketContract.withdraw();
    }

    function test_fulfillRandomWords() public onlyAnvil() purchaseNFTs(4) {      
        Vm.Log[] memory entries;
        uint256 requestId;
        vm.recordLogs();

        vm.prank(USER1);
        marketContract.purchase{value: 0.14641 ether}();
            
        entries = vm.getRecordedLogs();
        requestId = uint256(entries[4].topics[1]);

        
        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(
            requestId,
            address(marketContract)
        );        

        assertFalse(marketContract.paused(), "Market shouldn't be paused");
        
    }

    function test_fulfillRandomWords_ForcingPause() public onlyAnvil() purchaseNFTs(4) {      
        Vm.Log[] memory entries;
        uint256 requestId;
        vm.recordLogs();
        uint256[] memory notRandomWords = new uint256[](1);
        notRandomWords[0] = uint256(10);

        vm.prank(USER1);
        marketContract.purchase{value: 0.14641 ether}();
            
        entries = vm.getRecordedLogs();
        requestId = uint256(entries[4].topics[1]);

        
        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWordsWithOverride(
            requestId,
            address(marketContract),
            notRandomWords
        ); 
        
        assertTrue(marketContract.paused(), "Market should be paused");
    }

    // In this test we are using the Fuzzing technique to test the fulfillRandomWords function.
    // In that way, we can see if the function is working properly with different inputs. Aka, we can see when the market should be paused.
    // The function will be called with a random word as a parameter. If the random word is divisible by 10, the market should be paused.
    // So, the odds of the market being paused are 10%. Therefore, the test should revert in one of the first 10 calls. (Average)
    function test_fulfillRandomWords_Fuzzing(uint256 randomWord) public onlyAnvil() purchaseNFTs(4) {      
        Vm.Log[] memory entries;
        uint256 requestId;
        vm.recordLogs();
        uint256[] memory notRandomWords = new uint256[](1);
        notRandomWords[0] = randomWord;

        vm.prank(USER1);
        marketContract.purchase{value: 0.14641 ether}();
            
        entries = vm.getRecordedLogs();
        requestId = uint256(entries[4].topics[1]);

        
        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWordsWithOverride(
            requestId,
            address(marketContract),
            notRandomWords
        ); 

        if(randomWord % 10 == 0){
            console.log("Market should be paused");
            assertTrue(marketContract.paused(), "Market should be paused");
        }

        vm.prank(USER1);
        marketContract.purchase{value: 0.161051 ether}();
    }
}

