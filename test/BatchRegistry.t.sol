// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ParticipantRegistry} from "../src/ParticipantRegistry.sol";
import {BatchRegistry} from "../src/BatchRegistry.sol";

contract BatchRegistryTest is Test {
    ParticipantRegistry internal participants;
    BatchRegistry internal batches;

    address internal farm = address(0x1001);
    address internal processor = address(0x1002);
    address internal logistics = address(0x1003);
    address internal retailer = address(0x1004);

    function setUp() public {
        participants = new ParticipantRegistry();
        batches = new BatchRegistry(address(participants));

        participants.registerParticipant(farm, ParticipantRegistry.Role.Farm, "Farm");

        participants.registerParticipant(processor, ParticipantRegistry.Role.Processor, "Processor");

        participants.registerParticipant(logistics, ParticipantRegistry.Role.Logistics, "Logistics");

        participants.registerParticipant(retailer, ParticipantRegistry.Role.Retailer, "Retailer");
    }

    function testFarmCreatesBatch() public {
        vm.prank(farm);
        uint256 batchId = batches.createBatch(keccak256("MILK-001"));

        BatchRegistry.Batch memory batch = batches.getBatch(batchId);

        assertEq(batch.creator, farm);
        assertEq(batch.currentCustodian, farm);
        assertEq(uint256(batch.status), uint256(BatchRegistry.Status.Created));
    }

    function testValidCustodySequence() public {
        vm.prank(farm);
        uint256 batchId = batches.createBatch(keccak256("MILK-001"));

        vm.prank(farm);
        batches.transferCustody(batchId, processor);

        vm.prank(processor);
        batches.transferCustody(batchId, logistics);

        vm.prank(logistics);
        batches.transferCustody(batchId, retailer);

        BatchRegistry.Batch memory batch = batches.getBatch(batchId);

        assertEq(batch.currentCustodian, retailer);
        assertEq(uint256(batch.status), uint256(BatchRegistry.Status.Delivered));
        assertEq(batch.custodyTransfers, 3);
    }

    function testInvalidCustodySequenceReverts() public {
        vm.prank(farm);
        uint256 batchId = batches.createBatch(keccak256("MILK-002"));

        vm.prank(farm);
        vm.expectRevert(BatchRegistry.InvalidCustodyTransition.selector);

        batches.transferCustody(batchId, logistics);
    }

    function testNonFarmCannotCreateBatch() public {
        vm.prank(processor);
        vm.expectRevert(BatchRegistry.OnlyFarmCanCreate.selector);

        batches.createBatch(keccak256("INVALID"));
    }
}
