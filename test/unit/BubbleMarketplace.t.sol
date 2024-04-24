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
    address public vrfCoordinatorV2;
    HelperConfig public helperConfig;

    address public constant USER1 = address(0x1);
    address public constant ANVIL_DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public constant SEPOLIA_DEPLOYER = 0x97aa42A297049DD6078B97d4C1f9d384B52f5905;
    address public constant ARTISTS = address(0x91A8ACC8B933ffb6182c72dC9B45DEF7d6Ce7a0E);
    
    address public DEPLOYER;

   
    /************************************** Modifiers **************************************/
    
    modifier purchaseNFTs(uint256 amount) {
        uint256 lastPrice = 0.05 ether;
        
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

        uint256 lastPrice = 0.05 ether;
        
        for(uint256 i = 0; i < 5; i++){
            if(i == 1){
                vm.warp(block.timestamp + marketContract.INITIAL_LOTTERY_DELAY());
            }
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
        assertEq(marketContract.ARTISTS(), ARTISTS, "Incorrect fee recipient");
        assertEq(marketContract.currentPrice(), 0.05 ether, "Incorrect price");
        assertEq(marketContract.NUM_NFTS(), 10, "Incorrect number of nfts");
        assertEq(marketContract.FEE_PERCENTAGE(), 10, "Incorrect fee percentage");
        assertEq(marketContract.PRICE_INCREMENT_PERCENTAGE(), 10, "Incorrect fee percentage");
        assertEq(marketContract.LOTTERY_TRIGGER_INTERVAL(), 5, "Incorrect fee percentage");
        assertEq(marketContract.INITIAL_LOTTERY_DELAY(), 90 days, "Incorrect fee percentage");
        assertEq(marketContract.SECOND_LOTTERY_DELAY(), 130 days, "Incorrect fee percentage");
        assertEq(marketContract.THIRD_LOTTERY_DELAY(), 170 days, "Incorrect fee percentage");
        assertEq(marketContract.MAX_MARKETPLACE_OPERATION_DAYS(), 210 days, "Incorrect fee percentage");
        assertEq(marketContract.LOCK_DURATION(), 481 days, "Incorrect lock duration");
        for(uint256 i = 0; i < 10; i++){
            assertEq(nftContract.ownerOf(i), ARTISTS, "Incorrect owner of the NFT");
        }
    }

    function test_purchase() public { 
        // Check the state before the purchase  
        assertEq(marketContract.sellingNftId(), 0, "Incorrect selling nft id");
        assertEq(marketContract.nftsSold(), 0, "Incorrect nfts sold");
        assertEq(marketContract.currentPrice(), 0.05 ether, "Incorrect price");
        assertEq(marketContract.DEPLOYMENT_TIMESTAMP(), block.timestamp, "Incorrect deployment timestamp");
        assertEq(marketContract.firstMandatoryLotteryDone(), false, "Incorrect first mandatory lottery done");
        assertEq(marketContract.secondMandatoryLotteryDone(), false, "Incorrect second mandatory lottery done");
        assertEq(marketContract.lockTimestamp(), 0, "Incorrect lock timestamp");

        // Obtain the initial balances of the fee recipient and the NFT owner
        uint256 feeRecipientPreviousBalance = ARTISTS.balance;
        address owner = nftContract.ownerOf(0);
        uint256 ownerPreviousBalanceInContract = marketContract.getBalance(owner);

        // Purchase the NFT
        vm.prank(USER1);
        marketContract.purchase{value: 0.05 ether}();

        // Check the state after the purchase
        assertEq(marketContract.currentPrice(), 0.055 ether, "Incorrect price");
        assertEq(marketContract.nftsSold(), 1, "Incorrect nfts sold");
        assertEq(marketContract.sellingNftId(), 1, "Incorrect selling nft id");
        assertEq(ARTISTS.balance, feeRecipientPreviousBalance + 0.005 ether, "Incorrect fee recipient balance");
        assertEq(marketContract.getBalance(owner), ownerPreviousBalanceInContract + 0.045 ether, "Incorrect owner balance in contract");
        assertEq(nftContract.ownerOf(0), USER1, "Incorrect new owner of the NFT");  
        assertEq(marketContract.DEPLOYMENT_TIMESTAMP(), block.timestamp, "Incorrect deployment timestamp");
        assertEq(marketContract.firstMandatoryLotteryDone(), false, "Incorrect first mandatory lottery done");
        assertEq(marketContract.secondMandatoryLotteryDone(), false, "Incorrect second mandatory lottery done");   
    }

    /**
     * @dev Function to test the purchase of 35 NFTs.
     */
    function test_purchase_35() public {
        uint256 lastPrice = 0.05 ether;  
        
        // Purchase 35 NFTs
        for(uint256 purchaseCount = 0; purchaseCount <= 34; purchaseCount++){
            // Obtain the balances of the fee recipient and the NFT owner
            uint256 feeRecipientPreviousBalance = ARTISTS.balance;
            address owner = nftContract.ownerOf((purchaseCount)%10);
            uint256 ownerPreviousBalanceInContract = marketContract.getBalance(owner);

            // Purchase an NFT
            vm.deal(address(0x15), address(0x15).balance + lastPrice);
            vm.prank(address(0x15));
            marketContract.purchase{value: lastPrice}();
            
            // Check the state after each purchase
            assertEq(marketContract.currentPrice(), (lastPrice*110)/100, "Incorrect price");
            assertEq(marketContract.nftsSold(), purchaseCount+1, "Incorrect nfts sold");
            assertEq(marketContract.sellingNftId(), (purchaseCount+1)%10, "Incorrect selling nft id");
            assertEq(ARTISTS.balance, feeRecipientPreviousBalance + (lastPrice*marketContract.FEE_PERCENTAGE())/100, "Incorrect fee recipient balance");
            assertEq(marketContract.getBalance(owner), ownerPreviousBalanceInContract + (lastPrice - ((lastPrice*marketContract.FEE_PERCENTAGE())/100)), "Incorrect owner balance in contract");
            assertEq(nftContract.ownerOf((purchaseCount)%10), address(0x15), "Incorrect new owner of the NFT");
            assertEq(marketContract.firstMandatoryLotteryDone(), false, "Incorrect first mandatory lottery done");
            assertEq(marketContract.secondMandatoryLotteryDone(), false, "Incorrect second mandatory lottery done");   
            lastPrice = (lastPrice*110)/100;  
        }                                 
                       
    }
    
    /**
     * @dev Function to test the purchase of 35 NFTs.
     */
    function test_purchase_35_AfterInitialLotteryDelay() public purchaseNFTs(1){
        vm.warp(block.timestamp + marketContract.INITIAL_LOTTERY_DELAY());   
        uint256 lastPrice = 0.055 ether;
        Vm.Log[] memory entries;
        uint256 lastRequestId;     
        vm.recordLogs();
        
        // Purchase 35 NFTs
        for(uint256 purchaseCount = 1; purchaseCount <= 35; purchaseCount++){
            // Obtain the balances of the fee recipient and the NFT owner
            uint256 feeRecipientPreviousBalance = ARTISTS.balance;
            address owner = nftContract.ownerOf((purchaseCount)%10);
            uint256 ownerPreviousBalanceInContract = marketContract.getBalance(owner);

            // Purchase an NFT
            vm.deal(address(0x15), address(0x15).balance + lastPrice);
            vm.prank(address(0x15));
            marketContract.purchase{value: lastPrice}();
            if((purchaseCount+1) % 5 == 0){     
                // Chainlink requestRandomWords           
                entries = vm.getRecordedLogs();
                    if(purchaseCount == 4){
                    // Check the requestId retuned by the requestRandomWords function
                    assertTrue((uint256(entries[13].topics[1]) > 0) && (uint256(entries[13].topics[1]) != lastRequestId), "Incorrect requestId");
                    lastRequestId = uint256(entries[13].topics[1]);
                    }else{
                    // Check the requestId retuned by the requestRandomWords function
                    assertTrue((uint256(entries[16].topics[1]) > 0) && (uint256(entries[16].topics[1]) != lastRequestId), "Incorrect requestId");
                    lastRequestId = uint256(entries[16].topics[1]);
                }
            }
            
            // Check the state after each purchase
            assertEq(marketContract.currentPrice(), (lastPrice*110)/100, "Incorrect price");
            assertEq(marketContract.nftsSold(), purchaseCount+1, "Incorrect nfts sold");
            assertEq(marketContract.sellingNftId(), (purchaseCount+1)%10, "Incorrect selling nft id");
            assertEq(ARTISTS.balance, feeRecipientPreviousBalance + (lastPrice*marketContract.FEE_PERCENTAGE())/100, "Incorrect fee recipient balance");
            assertEq(marketContract.getBalance(owner), ownerPreviousBalanceInContract + (lastPrice - ((lastPrice*marketContract.FEE_PERCENTAGE())/100)), "Incorrect owner balance in contract");
            assertEq(nftContract.ownerOf((purchaseCount)%10), address(0x15), "Incorrect new owner of the NFT");
            assertEq(marketContract.firstMandatoryLotteryDone(), false, "Incorrect first mandatory lottery done");
            assertEq(marketContract.secondMandatoryLotteryDone(), false, "Incorrect second mandatory lottery done");   
            lastPrice = (lastPrice*110)/100;  
        }                                 
                       
    }

    function test_purchase_RevertIf_NotEnoughValue() public {
        // Purchase the NFT with insufficient funds
        vm.prank(USER1);
        vm.expectRevert(bytes("Insufficient funds to purchase NFT"));
        marketContract.purchase{value: 0.045 ether}();
    }

    function test_purchase_RevertIf_MarketIsPaused() public onlyAnvil() purchase5NFTsAndFullfillWithSelectedWords() {
        vm.prank(USER1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));   
        marketContract.purchase{value: 0.0805255 ether}();        
    }

    function test_withdraw() public purchaseNFTs(1){
        // Check the state before the withdrawal
        assertEq(marketContract.getBalance(ARTISTS), 0.045 ether, "Incorrect balance");
        
        uint256 ownerPreviousBalance = ARTISTS.balance;
        
        // Withdraw the balance
        vm.prank(ARTISTS);
        marketContract.withdraw();
        
        // Check the state after the withdrawal
        assertEq(marketContract.getBalance(ARTISTS), 0, "Incorrect balance");
        assertEq(ARTISTS.balance, ownerPreviousBalance + 0.045 ether, "Incorrect balance");
    }

    function test_withdraw_WhilePaused() public onlyAnvil() purchase5NFTsAndFullfillWithSelectedWords() {
        assertEq(marketContract.getBalance(ARTISTS), 0.2747295 ether, "Incorrect balance"); //5 sells
        uint256 previousBalance = ARTISTS.balance;
        vm.prank(ARTISTS);
        marketContract.withdraw();
        assertEq(marketContract.getBalance(ARTISTS), 0, "Incorrect balance");
        assertEq(ARTISTS.balance, previousBalance + 0.2747295 ether, "Incorrect balance");
    }

    function test_withdraw_RevertIf_InsufficientBalance() public {
        // Check the state before the withdrawal
        assertEq(marketContract.getBalance(USER1), 0, "Incorrect balance");
        
        // Withdraw the balance
        vm.prank(USER1);
        vm.expectRevert(bytes("Insufficient balance"));
        marketContract.withdraw();
    }

    function test_tryLock() public {
        vm.expectRevert(bytes("Not the right time to lock the marketplace"));
        marketContract.tryLock();

        assertEq(marketContract.firstMandatoryLotteryDone(), false, "Incorrect first mandatory lottery done");
        assertEq(marketContract.secondMandatoryLotteryDone(), false, "Incorrect second mandatory lottery done"); 
        assertEq(marketContract.paused(), false, "Market shouldn't be paused");

        vm.warp(block.timestamp + marketContract.SECOND_LOTTERY_DELAY());   
        marketContract.tryLock();

        assertEq(marketContract.firstMandatoryLotteryDone(), true, "Incorrect first mandatory lottery done");
        assertEq(marketContract.secondMandatoryLotteryDone(), false, "Incorrect second mandatory lottery done"); 
        assertEq(marketContract.paused(), false, "Market shouldn't be paused");

        vm.expectRevert(bytes("Not the right time to lock the marketplace"));
        marketContract.tryLock();

        vm.warp(block.timestamp - marketContract.SECOND_LOTTERY_DELAY() + marketContract.THIRD_LOTTERY_DELAY());   
        marketContract.tryLock();

        assertEq(marketContract.firstMandatoryLotteryDone(), true, "Incorrect first mandatory lottery done");
        assertEq(marketContract.secondMandatoryLotteryDone(), true, "Incorrect second mandatory lottery done"); 
        assertEq(marketContract.paused(), false, "Market shouldn't be paused");

        vm.expectRevert(bytes("Not the right time to lock the marketplace"));
        marketContract.tryLock();

        assertEq(marketContract.paused(), false, "Market shouldn't be paused");
        assertEq(marketContract.lockTimestamp(), 0, "Incorrect lock timestamp");

        vm.warp(block.timestamp + marketContract.MAX_MARKETPLACE_OPERATION_DAYS());   
        marketContract.tryLock();

        assertEq(marketContract.firstMandatoryLotteryDone(), true, "Incorrect first mandatory lottery done");
        assertEq(marketContract.secondMandatoryLotteryDone(), true, "Incorrect second mandatory lottery done"); 
        assertEq(marketContract.paused(), true, "Market shouldn't be paused");
        assertEq(marketContract.lockTimestamp(), block.timestamp, "Incorrect lock timestamp");
    }

    function test_tryLock_WithAcumulatedLotteries() public {
        vm.warp(block.timestamp + marketContract.MAX_MARKETPLACE_OPERATION_DAYS());   
        marketContract.tryLock();

        assertEq(marketContract.firstMandatoryLotteryDone(), true, "Incorrect first mandatory lottery done");
        assertEq(marketContract.secondMandatoryLotteryDone(), false, "Incorrect second mandatory lottery done"); 
        assertEq(marketContract.paused(), false, "Market shouldn't be paused");

        marketContract.tryLock();

        assertEq(marketContract.firstMandatoryLotteryDone(), true, "Incorrect first mandatory lottery done");
        assertEq(marketContract.secondMandatoryLotteryDone(), true, "Incorrect second mandatory lottery done"); 
        assertEq(marketContract.paused(), false, "Market shouldn't be paused");
  
        marketContract.tryLock();

        assertEq(marketContract.paused(), true, "Market shouldn't be paused");
        assertEq(marketContract.lockTimestamp(), block.timestamp, "Incorrect lock timestamp");
    }

    function test_tryLock_RevertIf_MarketIsPaused() public onlyAnvil() purchase5NFTsAndFullfillWithSelectedWords() {
        assertEq(marketContract.paused(), true, "Market should be paused");
        assertEq(marketContract.lockTimestamp(), block.timestamp, "Incorrect lock timestamp");

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));    
        marketContract.tryLock();

        assertEq(marketContract.paused(), true, "Market should be paused");
        assertEq(marketContract.lockTimestamp(), block.timestamp, "Incorrect lock timestamp");
    }

    function test_release() public onlyAnvil() purchase5NFTsAndFullfillWithSelectedWords() {
        assertTrue(nftContract.regulatedState(), "Incorrect NFT regulated state");
        vm.warp(block.timestamp + marketContract.LOCK_DURATION());
        marketContract.release();
        assertFalse(nftContract.regulatedState(), "Incorrect NFT regulated state");
    }

    function test_release_RevertIf_LockDurationNotElapsed() public onlyAnvil() purchase5NFTsAndFullfillWithSelectedWords() {
        vm.expectRevert(bytes("Lock duration not yet elapsed"));
        marketContract.release();
    }

    function test_release_RevertIf_MarketIsNotPaused() public {
        vm.expectRevert(abi.encodeWithSignature("ExpectedPause()"));        
        marketContract.release();
    }

    function test_fulfillRandomWords() public onlyAnvil() purchaseNFTs(4) { 
        vm.warp(block.timestamp + marketContract.INITIAL_LOTTERY_DELAY());     
        Vm.Log[] memory entries;
        uint256 requestId;
        vm.recordLogs();

        vm.prank(USER1);
        marketContract.purchase{value: 0.073205 ether}();
            
        entries = vm.getRecordedLogs();
        requestId = uint256(entries[4].topics[1]);

        
        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(
            requestId,
            address(marketContract)
        );        

        assertFalse(marketContract.paused(), "Market shouldn't be paused");
        
    }

    function test_fulfillRandomWords_ForcingPause() public onlyAnvil() purchaseNFTs(4) {      
        vm.warp(block.timestamp + marketContract.INITIAL_LOTTERY_DELAY());    
        Vm.Log[] memory entries;
        uint256 requestId;
        vm.recordLogs();
        uint256[] memory notRandomWords = new uint256[](1);
        notRandomWords[0] = uint256(10);

        vm.prank(USER1);
        marketContract.purchase{value: 0.073205 ether}();
            
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
        vm.warp(block.timestamp + marketContract.INITIAL_LOTTERY_DELAY());       
        Vm.Log[] memory entries;
        uint256 requestId;
        vm.recordLogs();
        uint256[] memory notRandomWords = new uint256[](1);
        notRandomWords[0] = randomWord;

        vm.prank(USER1);
        marketContract.purchase{value: 0.073205 ether}();
            
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
            vm.prank(USER1);
            vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
            marketContract.purchase{value: 0.073205 ether}();
        }

    }
}

