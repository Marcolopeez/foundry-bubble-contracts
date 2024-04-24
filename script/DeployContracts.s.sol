// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {BubbleMarketplace} from "../src/BubbleMarketplace.sol";
import {BubbleNFT} from "../src/BubbleNFT.sol";
import {AddConsumer, CreateSubscription, FundSubscription} from "./Interactions.s.sol";

contract DeployContracts is Script {

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

    function run() external returns (BubbleMarketplace, BubbleNFT, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig(); 
        AddConsumer addConsumer = new AddConsumer();
        (
            uint64 subscriptionId,
            bytes32 gasLane,
            uint32 callbackGasLimit,
            address vrfCoordinatorV2,
            address link,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        if (subscriptionId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            (subscriptionId, vrfCoordinatorV2) = createSubscription.createSubscription(
                vrfCoordinatorV2,
                deployerKey
            );
            if(block.chainid != 1) {
                FundSubscription fundSubscription = new FundSubscription();
                fundSubscription.fundSubscription(
                    vrfCoordinatorV2,
                    subscriptionId,
                    link,
                    deployerKey
                );
            }
        }

        vm.startBroadcast(deployerKey);
        
        BubbleNFT nftContract =  new BubbleNFT(metadataURIs, ARTISTS);
        BubbleMarketplace marketContract = new BubbleMarketplace(
            address(nftContract), 
            payable(ARTISTS), 
            INITIAL_PRICE,
            vrfCoordinatorV2,
            gasLane,
            subscriptionId,
            callbackGasLimit);

        // Set the marketplace contract as the NFT contract's market
        nftContract.setMarket(address(marketContract));
        vm.stopBroadcast();

        // We already have a broadcast in here
        addConsumer.addConsumer(
            address(marketContract),
            vrfCoordinatorV2,
            subscriptionId,
            deployerKey
        );
        return (marketContract, nftContract, helperConfig);
    }
}