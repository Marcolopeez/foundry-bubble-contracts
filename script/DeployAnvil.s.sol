// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {BubbleMarketplace} from "../src/BubbleMarketplace.sol";
import {BubbleNFT} from "../src/BubbleNFT.sol";
import {VRFCoordinatorV2Mock} from "../test/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

contract DeployAnvil is Script {

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

    bytes32 public constant GAS_LANE = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;  // Doesn't matters for anvil
    uint32 public constant CALLBACK_GAS_LIMIT = 250000;                                                     // 250,000 gas
    VRFCoordinatorV2Mock public vrfCoordinatorV2Mock;                                                       // vrfCoordinatorV2Mock      
    LinkToken public link;                                                                                  // linkMock

    uint96 public constant FUND_AMOUNT = 30 ether;

    function run() external returns (BubbleMarketplace, BubbleNFT, address) {
        uint64 subId;
        console.log("msg.sender: ", msg.sender);
        
        uint96 baseFee = 0.25 ether;
        uint96 gasPriceLink = 1e9;

        vm.startBroadcast();//----------------------------------------------------------------------------------------

        // Lets deploy the mocks (VRFCoordinatorV2 and LinkToken)-----------------------------------------------------
        vrfCoordinatorV2Mock = new VRFCoordinatorV2Mock(
            baseFee,
            gasPriceLink
        );
        link = new LinkToken();
        
        // Create subscription and fund it----------------------------------------------------------------------------
        subId = VRFCoordinatorV2Mock(vrfCoordinatorV2Mock).createSubscription();
        VRFCoordinatorV2Mock(vrfCoordinatorV2Mock).fundSubscription(
            subId,
            FUND_AMOUNT
        );
        
        // Deploy the NFT and Marketplace contracts-------------------------------------------------------------------
        BubbleNFT nftContract =  new BubbleNFT(metadataURIs, ARTISTS);
        BubbleMarketplace marketContract = new BubbleMarketplace(
            address(nftContract), 
            payable(ARTISTS), 
            INITIAL_PRICE,
            address(vrfCoordinatorV2Mock),
            GAS_LANE,
            subId,
            CALLBACK_GAS_LIMIT);

        // Set the marketplace contract as the NFT contract's market
        nftContract.setMarket(address(marketContract));

        // Add the Marketplace as a consumer contract-----------------------------------------------------------------
        VRFCoordinatorV2Mock(vrfCoordinatorV2Mock).addConsumer(
            subId,
            address(marketContract)
        );

        vm.stopBroadcast();//-----------------------------------------------------------------------------------------
        

        console.log("ChainId: ", block.chainid);
        console.log("Your subscription Id is: ", subId);
        console.log("Funding subscription: ", subId);
        console.log("Using vrfCoordinator: ", address(vrfCoordinatorV2Mock));
        console.log("Adding consumer contract: ", address(marketContract));

        //------------------------------------------------------------------------------------------------------------

        return (marketContract, nftContract, address(vrfCoordinatorV2Mock));
    }
}