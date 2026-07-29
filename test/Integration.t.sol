// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ParticipantRegistry} from "../src/ParticipantRegistry.sol";
import {BatchRegistry} from "../src/BatchRegistry.sol";
import {ColdChainCompliance} from "../src/ColdChainCompliance.sol";

contract IntegrationTest is Test {
    ParticipantRegistry internal participantRegistry;
    BatchRegistry internal batchRegistry;
    ColdChainCompliance internal compliance;

    address internal farm = address(0x1001);
    address internal processor = address(0x1002);
    address internal logistics = address(0x1003);
    address internal retailer = address(0x1004);

    uint256 internal farmSensorKey = 0xA11CE;
    uint256 internal processorSensorKey = 0xB0B;
    uint256 internal logisticsSensorKey = 0xCAFE;

    address internal farmSensor;
    address internal processorSensor;
    address internal logisticsSensor;

    function setUp() public {
        farmSensor = vm.addr(farmSensorKey);
        processorSensor = vm.addr(processorSensorKey);
        logisticsSensor = vm.addr(logisticsSensorKey);

        participantRegistry = new ParticipantRegistry();
        batchRegistry = new BatchRegistry(address(participantRegistry));
        compliance = new ColdChainCompliance(address(participantRegistry), address(batchRegistry));
        batchRegistry.setComplianceContract(address(compliance));

        participantRegistry.registerParticipant(farm, ParticipantRegistry.Role.Farm, "Fresh Farm");
        participantRegistry.registerParticipant(processor, ParticipantRegistry.Role.Processor, "Milk Processor");
        participantRegistry.registerParticipant(logistics, ParticipantRegistry.Role.Logistics, "Cold Logistics");
        participantRegistry.registerParticipant(retailer, ParticipantRegistry.Role.Retailer, "Retail Store");

        vm.prank(farm);
        participantRegistry.registerSensor(farmSensor);

        vm.prank(processor);
        participantRegistry.registerSensor(processorSensor);

        vm.prank(logistics);
        participantRegistry.registerSensor(logisticsSensor);
    }

    function testCompleteCompliantSupplyChainFlow() public {
        uint256 batchId = _createBatch("MILK-NORMAL-001");

        vm.prank(farm);
        batchRegistry.transferCustody(batchId, processor);

        uint64 processorMeasuredAt = uint64(block.timestamp);
        compliance.submitSignedReading(
            batchId, 40, processorMeasuredAt, 1, _signReading(processorSensorKey, batchId, 40, processorMeasuredAt, 1)
        );

        ColdChainCompliance.LatestReading memory processorReading = compliance.getLatestReading(batchId);
        assertEq(int256(processorReading.temperatureTenths), 40);
        assertEq(processorReading.sensor, processorSensor);
        assertFalse(processorReading.violation);

        vm.prank(processor);
        batchRegistry.transferCustody(batchId, logistics);

        vm.warp(block.timestamp + 1 minutes);
        uint64 logisticsMeasuredAt = uint64(block.timestamp);

        compliance.submitSignedReading(
            batchId, 50, logisticsMeasuredAt, 2, _signReading(logisticsSensorKey, batchId, 50, logisticsMeasuredAt, 2)
        );

        ColdChainCompliance.LatestReading memory logisticsReading = compliance.getLatestReading(batchId);
        assertEq(int256(logisticsReading.temperatureTenths), 50);
        assertEq(logisticsReading.sensor, logisticsSensor);
        assertFalse(logisticsReading.violation);

        vm.prank(logistics);
        batchRegistry.transferCustody(batchId, retailer);

        BatchRegistry.Batch memory finalBatch = batchRegistry.getBatch(batchId);
        assertEq(finalBatch.currentCustodian, retailer);
        assertEq(finalBatch.custodyTransfers, 3);
        assertEq(uint256(finalBatch.status), uint256(BatchRegistry.Status.Delivered));
    }

    function testTemperatureViolationTriggersRecallFlow() public {
        uint256 batchId = _createBatch("MILK-VIOLATION-001");

        vm.prank(farm);
        batchRegistry.transferCustody(batchId, processor);

        vm.prank(processor);
        batchRegistry.transferCustody(batchId, logistics);

        uint64 measuredAt = uint64(block.timestamp);
        compliance.submitSignedReading(
            batchId, 95, measuredAt, 10, _signReading(logisticsSensorKey, batchId, 95, measuredAt, 10)
        );

        ColdChainCompliance.LatestReading memory reading = compliance.getLatestReading(batchId);
        assertEq(int256(reading.temperatureTenths), 95);
        assertEq(reading.sensor, logisticsSensor);
        assertTrue(reading.violation);

        BatchRegistry.Batch memory nonCompliantBatch = batchRegistry.getBatch(batchId);
        assertEq(uint256(nonCompliantBatch.status), uint256(BatchRegistry.Status.NonCompliant));

        vm.prank(logistics);
        compliance.requestRecall(batchId, "Temperature exceeded the cold-chain threshold");

        BatchRegistry.Batch memory recalledBatch = batchRegistry.getBatch(batchId);
        assertEq(uint256(recalledBatch.status), uint256(BatchRegistry.Status.Recalled));
        assertEq(recalledBatch.currentCustodian, logistics);
    }

    function _createBatch(string memory name) internal returns (uint256 batchId) {
        bytes32 metadataHash = keccak256(bytes(name));

        vm.prank(farm);
        batchId = batchRegistry.createBatch(metadataHash);

        BatchRegistry.Batch memory batch = batchRegistry.getBatch(batchId);
        assertEq(batch.metadataHash, metadataHash);
        assertEq(batch.creator, farm);
        assertEq(batch.currentCustodian, farm);
        assertEq(uint256(batch.status), uint256(BatchRegistry.Status.Created));
    }

    function _signReading(
        uint256 privateKey,
        uint256 batchId,
        int16 temperatureTenths,
        uint64 measuredAt,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes32 digest = compliance.getReadingDigest(batchId, temperatureTenths, measuredAt, nonce);
        bytes32 signedDigest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, signedDigest);
        return abi.encodePacked(r, s, v);
    }
}
