// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {LOVE20GroupManager} from "../src/LOVE20GroupManager.sol";

/**
 * @title DeployGroupManager
 * @notice Script for deploying LOVE20GroupManager singleton contract
 * @dev Reads groupAddress, stakeAddress and joinAddress from params
 */
contract DeployGroupManager is BaseScript {
    address public groupManagerAddress;

    function run() external {
        address groupAddress = readAddressParamsFile(
            "address.group.params",
            "groupAddress"
        );
        address stakeAddress = readAddressParamsFile(
            "address.params",
            "stakeAddress"
        );
        address joinAddress = readAddressParamsFile(
            "address.params",
            "joinAddress"
        );
        require(groupAddress != address(0), "groupAddress not found");
        require(stakeAddress != address(0), "stakeAddress not found");
        require(joinAddress != address(0), "joinAddress not found");

        vm.startBroadcast();
        groupManagerAddress = address(
            new LOVE20GroupManager(groupAddress, stakeAddress, joinAddress)
        );
        vm.stopBroadcast();

        if (!hideLogs) {
            console.log("LOVE20GroupManager deployed at:", groupManagerAddress);
            console.log("Constructor parameters:");
            console.log("  groupAddress:", groupAddress);
            console.log("  stakeAddress:", stakeAddress);
            console.log("  joinAddress:", joinAddress);
        }

        updateParamsFile(
            "address.extension.group.params",
            "groupManagerAddress",
            vm.toString(groupManagerAddress)
        );
    }
}
