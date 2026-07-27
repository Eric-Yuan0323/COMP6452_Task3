// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ParticipantRegistry} from "../src/ParticipantRegistry.sol";
import {BatchRegistry} from "../src/BatchRegistry.sol";
import {ColdChainCompliance} from "../src/ColdChainCompliance.sol";

contract Interact is Script {
    function run() external {
        // Contract addresses
        address participantRegistryAddress =
            vm.envAddress("PARTICIPANT_REGISTRY");
        address batchRegistryAddress =
            vm.envAddress("BATCH_REGISTRY");
        address complianceAddress =
            vm.envAddress("COLD_CHAIN_COMPLIANCE");

        // Private keys
        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        uint256 farmPrivateKey = vm.envUint("FARM_PRIVATE_KEY");
        uint256 processorPrivateKey = vm.envUint("PROCESSOR_PRIVATE_KEY");
        uint256 logisticsPrivateKey = vm.envUint("LOGISTICS_PRIVATE_KEY");
        uint256 retailerPrivateKey = vm.envUint("RETAILER_PRIVATE_KEY");
        uint256 sensorPrivateKey = vm.envUint("SENSOR_PRIVATE_KEY");

        // Account addresses
        address admin = vm.addr(adminPrivateKey);
        address farm = vm.addr(farmPrivateKey);
        address processor = vm.addr(processorPrivateKey);
        address logistics = vm.addr(logisticsPrivateKey);
        address retailer = vm.addr(retailerPrivateKey);
        address sensor = vm.addr(sensorPrivateKey);

        ParticipantRegistry participantRegistry =
            ParticipantRegistry(participantRegistryAddress);

        BatchRegistry batchRegistry =
            BatchRegistry(batchRegistryAddress);

        ColdChainCompliance compliance =
            ColdChainCompliance(complianceAddress);

        // Basic deployment checks
        require(
            participantRegistry.administrator() == admin,
            "Wrong administrator private key"
        );

        require(
            batchRegistry.complianceContract() == complianceAddress,
            "Compliance contract linkage is incorrect"
        );

        console2.log("Administrator:", admin);
        console2.log("Farm:", farm);
        console2.log("Processor:", processor);
        console2.log("Logistics:", logistics);
        console2.log("Retailer:", retailer);
        console2.log("Sensor:", sensor);

        // ------------------------------------------------------------
        // 1. Register supply-chain participants
        // Existing participants are skipped, allowing safer re-runs.
        // ------------------------------------------------------------

        vm.startBroadcast(adminPrivateKey);

        if (
            participantRegistry.getRole(farm)
                == ParticipantRegistry.Role.None
        ) {
            participantRegistry.registerParticipant(
                farm,
                ParticipantRegistry.Role.Farm,
                "Green Valley Farm"
            );
        }

        if (
            participantRegistry.getRole(processor)
                == ParticipantRegistry.Role.None
        ) {
            participantRegistry.registerParticipant(
                processor,
                ParticipantRegistry.Role.Processor,
                "Fresh Milk Processing"
            );
        }

        if (
            participantRegistry.getRole(logistics)
                == ParticipantRegistry.Role.None
        ) {
            participantRegistry.registerParticipant(
                logistics,
                ParticipantRegistry.Role.Logistics,
                "Sydney Cold Logistics"
            );
        }

        if (
            participantRegistry.getRole(retailer)
                == ParticipantRegistry.Role.None
        ) {
            participantRegistry.registerParticipant(
                retailer,
                ParticipantRegistry.Role.Retailer,
                "Local Fresh Market"
            );
        }

        vm.stopBroadcast();

        // ------------------------------------------------------------
        // 2. Logistics company registers its IoT sensor
        // ------------------------------------------------------------

        ParticipantRegistry.Sensor memory storedSensor =
            participantRegistry.getSensor(sensor);

        if (storedSensor.operator == address(0)) {
            vm.startBroadcast(logisticsPrivateKey);
            participantRegistry.registerSensor(sensor);
            vm.stopBroadcast();
        } else {
            require(
                storedSensor.operator == logistics,
                "Sensor belongs to another operator"
            );
        }

        console2.log("Participants and sensor registered.");

        // ============================================================
        // Batch 1: compliant shipment delivered to retailer
        // ============================================================

        bytes32 compliantMetadataHash = keccak256(
            bytes(
                '{"batchReference":"MILK-001","product":"Fresh Milk","route":"compliant"}'
            )
        );

        vm.startBroadcast(farmPrivateKey);
        uint256 compliantBatchId =
            batchRegistry.createBatch(compliantMetadataHash);
        vm.stopBroadcast();

        console2.log("Compliant batch created:", compliantBatchId);

        // Farm -> Processor
        vm.startBroadcast(farmPrivateKey);
        batchRegistry.transferCustody(compliantBatchId, processor);
        vm.stopBroadcast();

        // Processor -> Logistics
        vm.startBroadcast(processorPrivateKey);
        batchRegistry.transferCustody(compliantBatchId, logistics);
        vm.stopBroadcast();

        // Normal temperature: 4.0 degrees Celsius
        uint64 normalMeasuredAt = uint64(block.timestamp);
        uint256 normalNonce = compliantBatchId * 1000 + 1;

        bytes memory normalSignature = _signReading(
            compliance,
            sensorPrivateKey,
            compliantBatchId,
            40,
            normalMeasuredAt,
            normalNonce
        );

        // Anyone may relay the reading. Logistics acts as relayer here.
        vm.startBroadcast(logisticsPrivateKey);
        compliance.submitSignedReading(
            compliantBatchId,
            40,
            normalMeasuredAt,
            normalNonce,
            normalSignature
        );
        vm.stopBroadcast();

        ColdChainCompliance.LatestReading memory normalReading =
            compliance.getLatestReading(compliantBatchId);

        console2.log(
            "Normal temperature (tenths C):",
            int256(normalReading.temperatureTenths)
        );
        console2.log("Normal reading violation:", normalReading.violation);

        // Logistics -> Retailer
        vm.startBroadcast(logisticsPrivateKey);
        batchRegistry.transferCustody(compliantBatchId, retailer);
        vm.stopBroadcast();

        BatchRegistry.Batch memory compliantBatch =
            batchRegistry.getBatch(compliantBatchId);

        console2.log(
            "Compliant batch final custodian:",
            compliantBatch.currentCustodian
        );
        console2.log(
            "Compliant batch final status:",
            uint256(compliantBatch.status)
        );
        console2.log(
            "Compliant batch custody transfers:",
            uint256(compliantBatch.custodyTransfers)
        );

        // ============================================================
        // Batch 2: temperature violation followed by recall
        // ============================================================

        bytes32 recalledMetadataHash = keccak256(
            bytes(
                '{"batchReference":"MILK-002","product":"Fresh Milk","route":"temperature-violation"}'
            )
        );

        vm.startBroadcast(farmPrivateKey);
        uint256 recalledBatchId =
            batchRegistry.createBatch(recalledMetadataHash);
        vm.stopBroadcast();

        console2.log("Recall-demo batch created:", recalledBatchId);

        // Farm -> Processor
        vm.startBroadcast(farmPrivateKey);
        batchRegistry.transferCustody(recalledBatchId, processor);
        vm.stopBroadcast();

        // Processor -> Logistics
        vm.startBroadcast(processorPrivateKey);
        batchRegistry.transferCustody(recalledBatchId, logistics);
        vm.stopBroadcast();

        // Abnormal temperature: 8.5 degrees Celsius
        // Maximum threshold is 6.0 degrees Celsius.
        uint64 abnormalMeasuredAt = uint64(block.timestamp);
        uint256 abnormalNonce = recalledBatchId * 1000 + 2;

        bytes memory abnormalSignature = _signReading(
            compliance,
            sensorPrivateKey,
            recalledBatchId,
            85,
            abnormalMeasuredAt,
            abnormalNonce
        );

        vm.startBroadcast(logisticsPrivateKey);
        compliance.submitSignedReading(
            recalledBatchId,
            85,
            abnormalMeasuredAt,
            abnormalNonce,
            abnormalSignature
        );
        vm.stopBroadcast();

        ColdChainCompliance.LatestReading memory abnormalReading =
            compliance.getLatestReading(recalledBatchId);

        BatchRegistry.Batch memory nonCompliantBatch =
            batchRegistry.getBatch(recalledBatchId);

        console2.log(
            "Abnormal temperature (tenths C):",
            int256(abnormalReading.temperatureTenths)
        );
        console2.log(
            "Abnormal reading violation:",
            abnormalReading.violation
        );
        console2.log(
            "Status after violation:",
            uint256(nonCompliantBatch.status)
        );

        // Current custodian requests recall
        vm.startBroadcast(logisticsPrivateKey);
        compliance.requestRecall(
            recalledBatchId,
            "Temperature exceeded the permitted cold-chain threshold"
        );
        vm.stopBroadcast();

        BatchRegistry.Batch memory recalledBatch =
            batchRegistry.getBatch(recalledBatchId);

        console2.log("Recalled batch ID:", recalledBatchId);
        console2.log(
            "Recalled batch custodian:",
            recalledBatch.currentCustodian
        );
        console2.log(
            "Recalled batch final status:",
            uint256(recalledBatch.status)
        );
        console2.log(
            "Recalled batch custody transfers:",
            uint256(recalledBatch.custodyTransfers)
        );

        console2.log("Sepolia interaction completed successfully.");
    }

    function _signReading(
        ColdChainCompliance compliance,
        uint256 sensorPrivateKey,
        uint256 batchId,
        int16 temperatureTenths,
        uint64 measuredAt,
        uint256 nonce
    ) internal view returns (bytes memory signature) {
        bytes32 digest = compliance.getReadingDigest(
            batchId,
            temperatureTenths,
            measuredAt,
            nonce
        );

        // ColdChainCompliance._recoverSigner() applies this prefix.
        bytes32 signedDigest = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                digest
            )
        );

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(sensorPrivateKey, signedDigest);

        signature = abi.encodePacked(r, s, v);
    }
}