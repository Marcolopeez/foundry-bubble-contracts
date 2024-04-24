// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {BubbleMarketplace} from "../src/BubbleMarketplace.sol";
import {BubbleNFT} from "../src/BubbleNFT.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

contract DeployMainnet is Script {

    string[10] public metadataURIs = [
        "ipfs://QmYpqMPXG9LjbQDXQSnc4WD3mRATwnyahe2bzDhRkHMDrS",
        "ipfs://Qmc6d74LpUenXR9W9KKqG9uad6bxzSH1aAbBpKHVj1KFRu",
        "ipfs://QmZmxD12CA5nnYkW8eKCHFwPiJ4vPtZvsuysEUWaHk3vvj",
        "ipfs://QmfLa8EkmfJfx9PceS6y9CZmJk5SSRM7e3H2qqaSuiJW4v",
        "ipfs://QmaecVZqH9Uc4SgDkxH4HePnYhTf3gpPaAdbE2hP4bHwXz",
        "ipfs://QmdP64p1YbfdRLmKXGLMC3knxDMxChZgYx5yEQzuNdkF4v",
        "ipfs://QmcXjdKPsTQReeYKpHx7bbycBuNtNVrrAVEZTXcQs5ez1S",
        "ipfs://QmZ8QJKr5DWjhyK4R5M6HAdGxjc7eWHi3xRBSg51xi4ycd",
        "ipfs://Qmco9M8QyNZSnPBsyqgt3fovo6xhs83EV6TCvbEU1Ppxzx",
        "ipfs://QmPk8a4YA6obwWVz7PcneMhVvxUN3jb4a8dTgxbj5EYQoZ"
        ];
    
    address public constant ARTISTS = address(0x91A8ACC8B933ffb6182c72dC9B45DEF7d6Ce7a0E);
    uint256 public constant INITIAL_PRICE = 0.05 ether;

    bytes32 public constant GAS_LANE = 0x8af398995b04c28e9951adb9721ef74c74f93e6a478f39e7e0777be13527e7ef;  // 250 gwei Key Hash
    uint32 public constant CALLBACK_GAS_LIMIT = 250000;                                                     // 250,000 gas
    address public constant VRF_COORDINATOR_V2 = 0x271682DEB8C4E0901D1a1550aD2e64D568E69909;                // vrfCoordinatorV2 in mainnet      
    
    function run() external returns (BubbleMarketplace, BubbleNFT, address) {
        uint64 subId = 0;
        console.log("msg.sender: ", msg.sender);

        vm.startBroadcast();//----------------------------------------------------------------------------------------

        // Create subscription---------------------------------------------------------------------------------------- 
        subId = VRFCoordinatorV2Interface(VRF_COORDINATOR_V2).createSubscription();      

        // Deploy the NFT and Marketplace contracts-------------------------------------------------------------------  
        BubbleNFT nftContract =  new BubbleNFT(metadataURIs, ARTISTS);
        BubbleMarketplace marketContract = new BubbleMarketplace(
            address(0x4F6F7E97e1dFea19663c4009B43E9d7DdcA41edA), 
            payable(ARTISTS), 
            INITIAL_PRICE,
            VRF_COORDINATOR_V2,
            GAS_LANE,
            subId,
            CALLBACK_GAS_LIMIT);

        // Set the marketplace contract as the NFT contract's market
        nftContract.setMarket(address(marketContract));

        // Add the Marketplace as a consumer contract-----------------------------------------------------------------
        VRFCoordinatorV2Interface(VRF_COORDINATOR_V2).addConsumer(
            subId,
            address(marketContract)
        );

        vm.stopBroadcast();//-----------------------------------------------------------------------------------------


        console.log("Creating subscription on chainId: ", block.chainid);
        console.log("Your subscription Id is: ", subId);
        console.log("Adding consumer contract: ", address(marketContract));
        console.log("Using vrfCoordinator: ", VRF_COORDINATOR_V2);
        console.log("On ChainID: ", block.chainid);

        //------------------------------------------------------------------------------------------------------------

        return (marketContract, nftContract, VRF_COORDINATOR_V2);
    }
}