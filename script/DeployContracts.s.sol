// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {BubbleMarketplace} from "../src/BubbleMarketplace.sol";
import {BubbleNFT} from "../src/BubbleNFT.sol";
import {AddConsumer, CreateSubscription, FundSubscription} from "./Interactions.s.sol";

contract DeployContracts is Script {

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
    
    address public constant FEE_RECIPIENT = address(0x4);
    address public constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function run() external returns (BubbleMarketplace, BubbleNFT, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig(); // This comes with our mocks!
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

            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(
                vrfCoordinatorV2,
                subscriptionId,
                link,
                deployerKey
            );
        }

        vm.startBroadcast(deployerKey);
        
        BubbleNFT nftContract =  new BubbleNFT(metadataURIs);
        BubbleMarketplace marketContract = new BubbleMarketplace(
            address(nftContract), 
            payable(FEE_RECIPIENT), 
            0.1 ether,
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