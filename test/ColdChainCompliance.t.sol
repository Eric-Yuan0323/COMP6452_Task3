// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ParticipantRegistry} from "../src/ParticipantRegistry.sol";
import {BatchRegistry} from "../src/BatchRegistry.sol";
import {ColdChainCompliance} from "../src/ColdChainCompliance.sol";

contract ColdChainComplianceTest is Test {
    ParticipantRegistry internal participants;
    BatchRegistry internal batches;
    ColdChainCompliance internal compliance;

    uint256 internal sensorPrivateKey = 0xBEEF;

    address internal farm = address(0x1001);
    address internal sensor;

    function setUp() public {
        sensor = vm.addr(sensorPrivateKey);

        participants = new ParticipantRegistry();
        batches = new BatchRegistry(address(participants));

        compliance = new ColdChainCompliance(address(participants), address(batches));

        batches.setComplianceContract(address(compliance));

        participants.registerParticipant(farm, ParticipantRegistry.Role.Farm, "Farm");

        vm.prank(farm);
        participants.registerSensor(sensor);

        vm.prank(farm);
        batches.createBatch(keccak256("MILK-001"));
    }

    function testValidTemperatureReading() public {
        uint64 measuredAt = uint64(block.timestamp);

        bytes memory signature = _signReading(1, 40, measuredAt, 1);

        compliance.submitSignedReading(1, 40, measuredAt, 1, signature);

        ColdChainCompliance.LatestReading memory reading = compliance.getLatestReading(1);

        assertEq(reading.temperatureTenths, 40);
        assertEq(reading.sensor, sensor);
        assertFalse(reading.violation);
    }

    function testViolationMarksBatchNonCompliant() public {
        uint64 measuredAt = uint64(block.timestamp);

        compliance.submitSignedReading(1, 90, measuredAt, 1, _signReading(1, 90, measuredAt, 1));

        BatchRegistry.Batch memory batch = batches.getBatch(1);

        assertEq(uint256(batch.status), uint256(BatchRegistry.Status.NonCompliant));
    }

    function testReplayedNonceReverts() public {
        uint64 measuredAt = uint64(block.timestamp);
        bytes memory signature = _signReading(1, 40, measuredAt, 7);

        compliance.submitSignedReading(1, 40, measuredAt, 7, signature);

        vm.expectRevert(ColdChainCompliance.NonceAlreadyUsed.selector);

        compliance.submitSignedReading(1, 40, measuredAt, 7, signature);
    }

    function testInvalidSensorSignatureReverts() public {
        uint64 measuredAt = uint64(block.timestamp);
        uint256 unknownPrivateKey = 0xCAFE;

        bytes32 digest = compliance.getReadingDigest(1, 40, measuredAt, 1);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(unknownPrivateKey, _ethereumSignedHash(digest));

        vm.expectRevert(ColdChainCompliance.SensorNotActive.selector);

        compliance.submitSignedReading(1, 40, measuredAt, 1, abi.encodePacked(r, s, v));
    }

    function testCurrentCustodianCanRequestRecall() public {
        vm.prank(farm);
        compliance.requestRecall(1, "Precautionary recall");

        BatchRegistry.Batch memory batch = batches.getBatch(1);

        assertEq(uint256(batch.status), uint256(BatchRegistry.Status.Recalled));
    }

    function _signReading(uint256 batchId, int16 temperatureTenths, uint64 measuredAt, uint256 nonce)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = compliance.getReadingDigest(batchId, temperatureTenths, measuredAt, nonce);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sensorPrivateKey, _ethereumSignedHash(digest));

        return abi.encodePacked(r, s, v);
    }

    function _ethereumSignedHash(bytes32 digest) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
    }

    function testDisabledSensorCannotSubmitReading() public {
        // Disable the sensor
        vm.prank(farm);
        participants.setSensorActive(sensor, false);

        uint64 measuredAt = uint64(block.timestamp);

        bytes memory signature =
            _signReading(1, 40, measuredAt, 1);

        vm.expectRevert(
            ColdChainCompliance.SensorNotActive.selector
        );

        compliance.submitSignedReading(
            1,
            40,
            measuredAt,
            1,
            signature
        );
    }
    
    function testExpiredTemperatureReadingReverts() public {
    // Move the blockchain time forward so that subtraction is safe.
    vm.warp(1 days);

    uint64 measuredAt = uint64(
        block.timestamp - compliance.maximumReadingAge() - 1
    );

    bytes memory signature =
        _signReading(1, 40, measuredAt, 2);

    vm.expectRevert();

    compliance.submitSignedReading(
        1,
        40,
        measuredAt,
        2,
        signature
    );
    }

    function testFutureTemperatureReadingReverts() public {
        uint64 measuredAt = uint64(block.timestamp + 60);

        bytes memory signature =
            _signReading(1, 40, measuredAt, 3);

        vm.expectRevert();

        compliance.submitSignedReading(
            1,
            40,
            measuredAt,
            3,
            signature
        );
    }

    function testSensorOwnedByPreviousCustodianReverts() public {
        address processor = address(0x1002);

        participants.registerParticipant(
            processor,
            ParticipantRegistry.Role.Processor,
            "Milk Processor"
        );

        // The batch moves from the farm to the processor.
        vm.prank(farm);
        batches.transferCustody(1, processor);

        // The sensor still belongs to the farm, which is no longer
        // the current custodian.
        uint64 measuredAt = uint64(block.timestamp);

        bytes memory signature =
            _signReading(1, 40, measuredAt, 4);

        vm.expectRevert();

        compliance.submitSignedReading(
            1,
            40,
            measuredAt,
            4,
            signature
        );
    }

    function testUnauthorisedUserCannotRecallBatch() public {
        address attacker = address(0x9999);

        vm.prank(attacker);
        vm.expectRevert();

        compliance.requestRecall(
            1,
            "Unauthorised recall attempt"
        );
    }
    
}
