// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "@forge-std/Test.sol";
import {BubbleNFT} from "../../src/BubbleNFT.sol";
import {BubbleMarketplace} from "../../src/BubbleMarketplace.sol";
import {DeployContracts} from "../../script/DeployContracts.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract BubbleNFT_Test is Test{
    BubbleNFT public nftContract;
    BubbleMarketplace public marketContract;
    HelperConfig public helperConfig;

    uint64 subscriptionId;
    bytes32 gasLane;
    uint256 automationUpdateInterval;
    uint256 raffleEntranceFee;
    uint32 callbackGasLimit;
    address vrfCoordinatorV2;

    address public constant USER1 = address(0x1);
    address public constant ANVIL_DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public constant SEPOLIA_DEPLOYER = 0x97aa42A297049DD6078B97d4C1f9d384B52f5905;
    address public constant FEE_RECIPIENT = address(0x3);
    
    address public DEPLOYER;

    string[10] public metadataURIs = [
        "ipfs://QmU2oxcpHVWpiGZZmshP1vihfCigUbzF14EMpA6GdKpcT8",
        "ipfs://QmbMytFCrjUCouwZAaJ81zMZaZdpKy4sEKS1evGuRo5f8z",
        "ipfs://QmTKfHTGTkyxVJ7Gn4Eezi1m6qF29sGNESA7hs6DCsHQ8k",
        "ipfs://QmXUwAFH7V6sFUDQtSyBFnQuWYbRRJWbH7m2EUNXLjzzhN",
        "ipfs://Qmcyc1iNNxpw7hmQu7NvTnapz9qmSH79CLdykjfxVXAPPa",
        "ipfs://QmcsE9h1vfVLCDKYtB8yerSNArAMxKBwGFLpj387miwC6p",
        "ipfs://QmVT4LocC1RMAFkHW8yu5mJBjKtbXWMqvhV3CDZdQsNNwc",
        "ipfs://QmXbRdqyHQUYtVXfC8GfFpNgVkxegDEwRd4XjP7DmAGMt4",
        "ipfs://QmdNG6pEr4ncVuutSjD3m5mGkuYaHDsdsa6bdXQugtkK6L",
        "ipfs://QmazRJRM6zAFezWVvNvKjnBx2i5g2CVWQJY2p4YvUJaHP3"
        ];
   
    /************************************** Modifiers **************************************/

    modifier releaseRestriction() {
        assertTrue(nftContract.regulatedState(), "Incorrect regulated state");

        vm.prank(address(marketContract));
        nftContract.releaseRestriction();
        _;
    }

    modifier approve(address caller, address to, uint256 tokenId) {
        vm.prank(caller);
        nftContract.approve(to, tokenId);
        _;
    }

    /************************************** Set Up **************************************/

    function setUp() public {
        vm.deal(USER1, 10 ether);

        DeployContracts deployer = new DeployContracts();
        (marketContract, nftContract, helperConfig) = deployer.run();
        (
            ,
            gasLane,
            callbackGasLimit,
            ,
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
        assertEq(nftContract.name(), "BubbleNFT", "Incorrect token name");
        assertEq(nftContract.symbol(), "BLE", "Incorrect symbol name");
        for(uint i=0; i<10; i++){
            assertEq(nftContract.ownerOf(i), DEPLOYER, "Incorrect owner of NFT");
            assertEq(nftContract.tokenURI(i), metadataURIs[i], "Incorrect metadata URI");
        }
        assertEq(nftContract.balanceOf(DEPLOYER), 10, "Incorrect balance of NFT");
        assertTrue(nftContract.hasRole(bytes32(nftContract.DEPLOYER_ROLE()), DEPLOYER), "Incorrect deployer role");
        assertTrue(nftContract.hasRole(bytes32(nftContract.MARKET_ROLE()), address(marketContract)), "Incorrect market role");
        assertTrue(nftContract.regulatedState(), "Incorrect regulated state");
    }

    function test_setMarket_RevertIf_MarketAddressAlreadySet() public {
        vm.prank(DEPLOYER);
        vm.expectRevert(bytes("Market address already set"));
        nftContract.setMarket(address(marketContract));
    }

    function test_setMarket_RevertIf_CallerIsNotDeployer() public {
        vm.prank(DEPLOYER);
        BubbleNFT nftContract2 = new BubbleNFT(["","","","","","","","","",""]);
        vm.prank(USER1);
        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", USER1, keccak256("DEPLOYER_ROLE")));
        nftContract2.setMarket(address(marketContract));        
    }

    function test_releaseRestriction() public releaseRestriction() {
        assertFalse(nftContract.regulatedState(), "Incorrect regulated state");
    }

    function test_releaseRestriction_RevertIf_NFTIsNotInRegulatedState() public releaseRestriction() {        
        vm.prank(address(marketContract));
        vm.expectRevert(bytes("Bubble NFT is not in a regulated state"));
        nftContract.releaseRestriction();
    }

    function test_releaseRestriction_RevertIf_CallerIsNotMarket() public {
        vm.prank(USER1);
        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", USER1, keccak256("MARKET_ROLE")));
        nftContract.releaseRestriction();
    }

    function test_approve_InRegulatedState() public approve(address(marketContract), address(marketContract), 0) {
        assertEq(nftContract.getApproved(0), address(marketContract), "Incorrect approved address");
    }

    function test_approve_InRegulatedState_RevertIf_CallerIsNotMarket() public {
        vm.prank(USER1);
        vm.expectRevert(bytes("Caller is not the marketplace"));
        nftContract.approve(USER1, 0);
    }

    function test_approve_InRegulatedState_RevertIf_OperatorIsNotMarket() public {
        vm.prank(address(marketContract));
        vm.expectRevert(bytes("Marketplace is the only approvable address"));
        nftContract.approve(USER1, 0);
    }

    function test_approve_InRegulatedState_RevertIf_TokenIdIsNotOwned() public {
        vm.prank(address(marketContract));
        vm.expectRevert(abi.encodeWithSignature("ERC721NonexistentToken(uint256)", 10));
        nftContract.approve(address(marketContract), 10);
    }

    function test_approve_InNoRegulatedState() public releaseRestriction() approve(DEPLOYER, USER1, 0) {
        assertEq(nftContract.getApproved(0), USER1, "Incorrect approved address");
    }

    function test_approve_InNoRegulatedState_RevertIf_CallerIsNotOwner() public releaseRestriction() {
        vm.prank(USER1);
        vm.expectRevert(abi.encodeWithSignature("ERC721InvalidApprover(address)", USER1));
        nftContract.approve(USER1, 0);
        assertEq(nftContract.getApproved(0), address(0), "Incorrect approved address");
    }

    function test_approve_InNoRegulatedState_RevertIf_TokenIdIsNotOwned() public releaseRestriction() {
        vm.prank(DEPLOYER);
        vm.expectRevert(abi.encodeWithSignature("ERC721NonexistentToken(uint256)", 10));
        nftContract.approve(USER1, 10);
    }

    function test_setApprovalForAll_RevertIf_InRegulatedState() public {
        vm.prank(DEPLOYER);
        vm.expectRevert(bytes("Set approval for all is not allowed in regulated state"));
        nftContract.setApprovalForAll(USER1, true);
    }

    function test_setApprovalForAll_RevertIf_InRegulatedState_ByMarket() public {
        vm.prank(address(marketContract));
        vm.expectRevert(bytes("Set approval for all is not allowed in regulated state"));
        nftContract.setApprovalForAll(USER1, true);
    }

    function test_setApprovalForAll_InNoRegulatedState() public releaseRestriction() {
        vm.prank(DEPLOYER);
        nftContract.setApprovalForAll(USER1, true);
        assertTrue(nftContract.isApprovedForAll(DEPLOYER, USER1), "Incorrect approved address");
    }

    function test_setApprovalForAll_InNoRegulatedState_RemoveApproval() public releaseRestriction() {
        vm.prank(DEPLOYER);
        nftContract.setApprovalForAll(USER1, true);
        assertTrue(nftContract.isApprovedForAll(DEPLOYER, USER1), "Incorrect approved address");
        
        vm.prank(DEPLOYER);
        nftContract.setApprovalForAll(USER1, false);
        assertFalse(nftContract.isApprovedForAll(DEPLOYER, USER1), "Incorrect approved address");
    }

    function test_setApprovalForAll_InNoRegulatedState_RevertIf_OperatorIsZeroAddress() public releaseRestriction() {
        vm.prank(USER1);
        vm.expectRevert(abi.encodeWithSignature("ERC721InvalidOperator(address)", address(0)));
        nftContract.setApprovalForAll(address(0), true);
    }

    function test_TransferFrom_InRegulatedState() public approve(address(marketContract), address(marketContract), 0) {
        vm.prank(address(marketContract));
        nftContract.transferFrom(DEPLOYER, USER1, 0);
        assertEq(nftContract.ownerOf(0), USER1, "Incorrect owner of NFT");
        assertEq(nftContract.balanceOf(USER1), 1, "Incorrect balance of NFT");
        assertEq(nftContract.balanceOf(DEPLOYER), 9, "Incorrect balance of NFT");
    }

    function test_TransferFrom_InRegulatedState_RevertIf_CallerIsNotMarket() public approve(address(marketContract), address(marketContract), 0) {
        vm.prank(USER1);
        vm.expectRevert(bytes("Caller is not the marketplace"));
        nftContract.transferFrom(DEPLOYER, USER1, 0);
        assertEq(nftContract.ownerOf(0), DEPLOYER, "Incorrect owner of NFT");
        assertEq(nftContract.balanceOf(USER1), 0, "Incorrect balance of NFT");
        assertEq(nftContract.balanceOf(DEPLOYER), 10, "Incorrect balance of NFT");
    }

    function test_TransferFrom_InRegulatedState_RevertIf_IsNotApproved() public {
        vm.prank(address(marketContract));
        vm.expectRevert(abi.encodeWithSignature("ERC721InsufficientApproval(address,uint256)", address(marketContract), 0));
        nftContract.transferFrom(DEPLOYER, USER1, 0);
        assertEq(nftContract.ownerOf(0), DEPLOYER, "Incorrect owner of NFT");
        assertEq(nftContract.balanceOf(USER1), 0, "Incorrect balance of NFT");
        assertEq(nftContract.balanceOf(DEPLOYER), 10, "Incorrect balance of NFT");
    } 

    function test_TransferFrom_InRegulatedState_RevertIf_TokenIdIsNotOwned() public {
        vm.prank(address(marketContract));
        vm.expectRevert(abi.encodeWithSignature("ERC721NonexistentToken(uint256)", 10));
        nftContract.transferFrom(DEPLOYER, USER1, 10);
        assertEq(nftContract.ownerOf(0), DEPLOYER, "Incorrect owner of NFT");
        assertEq(nftContract.balanceOf(USER1), 0, "Incorrect balance of NFT");
        assertEq(nftContract.balanceOf(DEPLOYER), 10, "Incorrect balance of NFT");
    }

    function test_TransferFrom_InRegulatedState_RevertIf_ReceiverIsZeroAddress() public approve(address(marketContract), address(marketContract), 0) {
        vm.prank(address(marketContract));
        vm.expectRevert(abi.encodeWithSignature("ERC721InvalidReceiver(address)", address(0)));
        nftContract.transferFrom(DEPLOYER, address(0), 0);
        assertEq(nftContract.ownerOf(0), DEPLOYER, "Incorrect owner of NFT");
        assertEq(nftContract.balanceOf(DEPLOYER), 10, "Incorrect balance of NFT");
    }

    function test_TransferFrom_InRegulatedState_RevertIf_IncorrectOwner() public approve(address(marketContract), address(marketContract), 0) {
        vm.prank(address(marketContract));
        vm.expectRevert(abi.encodeWithSignature("ERC721IncorrectOwner(address,uint256,address)", USER1, 0, DEPLOYER));
        nftContract.transferFrom(USER1, DEPLOYER, 0);
        assertEq(nftContract.ownerOf(0), DEPLOYER, "Incorrect owner of NFT");
        assertEq(nftContract.balanceOf(USER1), 0, "Incorrect balance of NFT");
        assertEq(nftContract.balanceOf(DEPLOYER), 10, "Incorrect balance of NFT");
    }
    
    function test_TransferFrom_InNoRegulatedState() public releaseRestriction() approve(DEPLOYER, USER1, 0) {
        vm.prank(USER1);
        nftContract.transferFrom(DEPLOYER, USER1, 0);
        assertEq(nftContract.ownerOf(0), USER1, "Incorrect owner of NFT");
        assertEq(nftContract.balanceOf(USER1), 1, "Incorrect balance of NFT");
        assertEq(nftContract.balanceOf(DEPLOYER), 9, "Incorrect balance of NFT");
    }

    function test_TransferFrom_InNoRegulatedState_ByOwner() public releaseRestriction() {
        vm.prank(DEPLOYER);
        nftContract.transferFrom(DEPLOYER, USER1, 0);
        assertEq(nftContract.ownerOf(0), USER1, "Incorrect owner of NFT");
        assertEq(nftContract.balanceOf(USER1), 1, "Incorrect balance of NFT");
        assertEq(nftContract.balanceOf(DEPLOYER), 9, "Incorrect balance of NFT");
    }

    function test_TransferFrom_InNoRegulatedState_RevertIf_IsNotApproved() public releaseRestriction() {
        vm.prank(USER1);
        vm.expectRevert(abi.encodeWithSignature("ERC721InsufficientApproval(address,uint256)", USER1, 0));
        nftContract.transferFrom(DEPLOYER, USER1, 0);
        assertEq(nftContract.ownerOf(0), DEPLOYER, "Incorrect owner of NFT");
        assertEq(nftContract.balanceOf(USER1), 0, "Incorrect balance of NFT");
        assertEq(nftContract.balanceOf(DEPLOYER), 10, "Incorrect balance of NFT");
    }

    function test_TransferFrom_InNoRegulatedState_RevertIf_ReceiverIsZeroAddress() public releaseRestriction() approve(DEPLOYER, USER1, 0) {
        vm.prank(USER1);
        vm.expectRevert(abi.encodeWithSignature("ERC721InvalidReceiver(address)", address(0)));
        nftContract.transferFrom(DEPLOYER, address(0), 0);
        assertEq(nftContract.ownerOf(0), DEPLOYER, "Incorrect owner of NFT");
        assertEq(nftContract.balanceOf(DEPLOYER), 10, "Incorrect balance of NFT");
    }

    function test_safeTransferFrom_RevertIf_InRegulatedState() public {
        vm.prank(DEPLOYER);
        vm.expectRevert(bytes("Safe transfer is not allowed in regulated state"));
        nftContract.safeTransferFrom(DEPLOYER, USER1, 0, "");
    }

    function test_safeTransferFrom_RevertIf_InRegulatedState_ByMarket() public {
        vm.prank(DEPLOYER);
        vm.expectRevert(bytes("Safe transfer is not allowed in regulated state"));
        nftContract.safeTransferFrom(DEPLOYER, USER1, 0, "");
    }

}