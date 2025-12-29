// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {GroupManager} from "../src/GroupManager.sol";

/**
 * @title DeployGroupManager
 * @notice Script for deploying GroupManager singleton contract
 * @dev Requires extensionCenter, group, stake, and join contracts to be deployed first
 */
contract DeployGroupManager is BaseScript {
    address public groupManagerAddress;

    function run() external {
        // Read addresses from params files
        address centerAddress = readAddressParamsFile(
            "address.extension.center.params",
            "centerAddress"
        );
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

        // Validate addresses are not zero
        require(
            centerAddress != address(0),
            "centerAddress not found in params"
        );
        require(groupAddress != address(0), "groupAddress not found in params");
        require(stakeAddress != address(0), "stakeAddress not found in params");
        require(joinAddress != address(0), "joinAddress not found in params");

        // Validate contracts are deployed (have code)
        require(
            centerAddress.code.length > 0,
            "extensionCenter contract not deployed"
        );
        require(groupAddress.code.length > 0, "group contract not deployed");
        require(stakeAddress.code.length > 0, "stake contract not deployed");
        require(joinAddress.code.length > 0, "join contract not deployed");

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
