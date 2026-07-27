// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ParticipantRegistry} from "../src/ParticipantRegistry.sol";

contract ParticipantRegistryTest is Test {
    ParticipantRegistry internal registry;

    address internal farm = address(0x1001);
    address internal sensor = address(0x2001);
    address internal attacker = address(0x3001);

    function setUp() public {
        registry = new ParticipantRegistry();

        registry.registerParticipant(farm, ParticipantRegistry.Role.Farm, "Fresh Farm");
    }

    function testAdministratorRegistersParticipant() public view {
        ParticipantRegistry.Participant memory participant = registry.getParticipant(farm);

        assertEq(participant.name, "Fresh Farm");
        assertEq(uint256(participant.role), uint256(ParticipantRegistry.Role.Farm));
        assertTrue(participant.active);
    }

    function testActiveParticipantRegistersSensor() public {
        vm.prank(farm);
        registry.registerSensor(sensor);

        assertTrue(registry.isActiveSensor(sensor));
        assertEq(registry.getSensorOperator(sensor), farm);
    }

    function testSensorOperatorCanDisableSensor() public {
        vm.prank(farm);
        registry.registerSensor(sensor);

        vm.prank(farm);
        registry.setSensorActive(sensor, false);

        assertFalse(registry.isActiveSensor(sensor));
    }

    function testUnauthorisedParticipantRegistrationReverts() public {
        vm.prank(attacker);
        vm.expectRevert(ParticipantRegistry.OnlyAdministrator.selector);

        registry.registerParticipant(attacker, ParticipantRegistry.Role.Logistics, "Attacker");
    }
}
