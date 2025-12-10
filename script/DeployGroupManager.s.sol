// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {LOVE20GroupManager} from "../src/LOVE20GroupManager.sol";

/**
 * @title DeployGroupManager
 * @notice Script for deploying LOVE20GroupManager singleton contract
 * @dev Requires extensionCenter, group, stake, and join contracts to be deployed first
 */
contract DeployGroupManager is BaseScript {
    address public groupManagerAddress;

    function run() external {
        // Read addresses from params files
        address centerAddress = readAddressParamsFile(
            "address.extension.center.params",
            "extensionCenterAddress"
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
        groupManagerAddress = address(
            new LOVE20GroupManager(
                centerAddress,
                groupAddress,
                stakeAddress,
                joinAddress
            )
        );
        vm.stopBroadcast();

        if (!hideLogs) {
            console.log("LOVE20GroupManager deployed at:", groupManagerAddress);
            console.log("Constructor parameters:");
            console.log("  centerAddress:", centerAddress);
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
