// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ParticipantRegistry} from "../src/ParticipantRegistry.sol";
import {BatchRegistry} from "../src/BatchRegistry.sol";
import {ColdChainCompliance} from "../src/ColdChainCompliance.sol";

contract Deploy is Script {
    function run()
        external
        returns (
            ParticipantRegistry participantRegistry,
            BatchRegistry batchRegistry,
            ColdChainCompliance coldChainCompliance
        )
    {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);

        // 1. Deploy participant and sensor registry
        participantRegistry = new ParticipantRegistry();

        // 2. Deploy milk batch and custody registry
        batchRegistry = new BatchRegistry(address(participantRegistry));

        // 3. Deploy cold-chain compliance contract
        coldChainCompliance = new ColdChainCompliance(address(participantRegistry), address(batchRegistry));

        // 4. Authorise ColdChainCompliance to update batch status
        batchRegistry.setComplianceContract(address(coldChainCompliance));

        vm.stopBroadcast();

        console2.log("ParticipantRegistry:", address(participantRegistry));
        console2.log("BatchRegistry:", address(batchRegistry));
        console2.log("ColdChainCompliance:", address(coldChainCompliance));
    }
}
