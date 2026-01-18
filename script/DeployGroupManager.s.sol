// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {GroupManager} from "../src/GroupManager.sol";

/**
 * @title DeployGroupManager
 * @notice Script for deploying GroupManager singleton contract
 */
contract DeployGroupManager is BaseScript {
    address public groupManagerAddress;

    function run() external {
        vm.startBroadcast();
        groupManagerAddress = address(new GroupManager());
        vm.stopBroadcast();

        if (!hideLogs) {
            console.log("GroupManager deployed at:", groupManagerAddress);
            console.log(
                "Note: GroupManager will be initialized by the Factory"
            );
        }

        updateParamsFile(
            "address.extension.group.params",
            "groupManagerAddress",
            vm.toString(groupManagerAddress)
        );
    }
}
