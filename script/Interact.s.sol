// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ParticipantRegistry} from "../src/ParticipantRegistry.sol";
import {BatchRegistry} from "../src/BatchRegistry.sol";

contract Interact is Script {
    function run() external {
        // Read deployed contract addresses
        address participantRegistryAddress = vm.envAddress("PARTICIPANT_REGISTRY");
        address batchRegistryAddress = vm.envAddress("BATCH_REGISTRY");

        // Read the private keys for each supply-chain role
        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        uint256 farmPrivateKey = vm.envUint("FARM_PRIVATE_KEY");
        uint256 processorPrivateKey = vm.envUint("PROCESSOR_PRIVATE_KEY");
        uint256 logisticsPrivateKey = vm.envUint("LOGISTICS_PRIVATE_KEY");
        uint256 retailerPrivateKey = vm.envUint("RETAILER_PRIVATE_KEY");

        // Derive participant addresses from their private keys
        address farm = vm.addr(farmPrivateKey);
        address processor = vm.addr(processorPrivateKey);
        address logistics = vm.addr(logisticsPrivateKey);
        address retailer = vm.addr(retailerPrivateKey);

        ParticipantRegistry participantRegistry = ParticipantRegistry(participantRegistryAddress);
        BatchRegistry batchRegistry = BatchRegistry(batchRegistryAddress);

        // 1. Administrator registers supply-chain participants
        vm.startBroadcast(adminPrivateKey);

        participantRegistry.registerParticipant(farm, ParticipantRegistry.Role.Farm, "Green Valley Farm");

        participantRegistry.registerParticipant(processor, ParticipantRegistry.Role.Processor, "Fresh Milk Processing");

        participantRegistry.registerParticipant(logistics, ParticipantRegistry.Role.Logistics, "Sydney Cold Logistics");

        participantRegistry.registerParticipant(retailer, ParticipantRegistry.Role.Retailer, "Local Fresh Market");

        vm.stopBroadcast();

        console2.log("Farm:", farm);
        console2.log("Processor:", processor);
        console2.log("Logistics:", logistics);
        console2.log("Retailer:", retailer);

        // 2. Farm creates a milk batch
        bytes32 metadataHash = keccak256(bytes('{"batchReference":"MILK-001","product":"Fresh Milk"}'));

        vm.startBroadcast(farmPrivateKey);
        uint256 batchId = batchRegistry.createBatch(metadataHash);
        vm.stopBroadcast();

        console2.log("Created batch ID:", batchId);

        // 3. Farm transfers the batch to the processor
        vm.startBroadcast(farmPrivateKey);
        batchRegistry.transferCustody(batchId, processor);
        vm.stopBroadcast();

        // 4. Processor transfers the batch to logistics
        vm.startBroadcast(processorPrivateKey);
        batchRegistry.transferCustody(batchId, logistics);
        vm.stopBroadcast();

        // 5. Logistics transfers the batch to the retailer
        vm.startBroadcast(logisticsPrivateKey);
        batchRegistry.transferCustody(batchId, retailer);
        vm.stopBroadcast();

        // 6. Read and display the final on-chain state
        BatchRegistry.Batch memory batch = batchRegistry.getBatch(batchId);

        console2.log("Final batch ID:", batchId);
        console2.log("Current custodian:", batch.currentCustodian);
        console2.log("Final status:", uint256(batch.status));
        console2.log("Custody transfers:", uint256(batch.custodyTransfers));
        console2.log("Interaction completed successfully.");
    }
}
