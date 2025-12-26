// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {
    LOVE20ExtensionGroupActionFactory
} from "../src/LOVE20ExtensionGroupActionFactory.sol";

/**
 * @title DeployGroupActionFactory
 * @notice Script for deploying LOVE20ExtensionGroupActionFactory contract
 * @dev Requires extensionCenter, GroupManager, and GroupDistrust contracts to be deployed first
 */
contract DeployGroupActionFactory is BaseScript {
    address public groupActionFactoryAddress;

    function run() external {
        // Read addresses from params files
        address centerAddress = readAddressParamsFile(
            "address.extension.center.params",
            "centerAddress"
        );
        address groupManagerAddress = readAddressParamsFile(
            "address.extension.group.params",
            "groupManagerAddress"
        );
        address groupDistrustAddress = readAddressParamsFile(
            "address.extension.group.params",
            "groupDistrustAddress"
        );

        // Validate addresses are not zero
        require(
            centerAddress != address(0),
            "centerAddress not found in params"
        );
        require(
            groupManagerAddress != address(0),
            "groupManagerAddress not found in params"
        );
        require(
            groupDistrustAddress != address(0),
            "groupDistrustAddress not found in params"
        );

        // Validate contracts are deployed (have code)
        require(
            centerAddress.code.length > 0,
            "extensionCenter contract not deployed"
        );
        require(
            groupManagerAddress.code.length > 0,
            "GroupManager contract not deployed"
        );
        require(
            groupDistrustAddress.code.length > 0,
            "GroupDistrust contract not deployed"
        );

        vm.startBroadcast();
        groupActionFactoryAddress = address(
            new LOVE20ExtensionGroupActionFactory(
                centerAddress,
                groupManagerAddress,
                groupDistrustAddress
            )
        );
        vm.stopBroadcast();

        if (!hideLogs) {
            console.log(
                "LOVE20ExtensionGroupActionFactory deployed at:",
                groupActionFactoryAddress
            );
            console.log("Constructor parameters:");
            console.log("  centerAddress:", centerAddress);
            console.log("  groupManagerAddress:", groupManagerAddress);
            console.log("  groupDistrustAddress:", groupDistrustAddress);
        }

        updateParamsFile(
            "address.extension.group.params",
            "groupActionFactoryAddress",
            vm.toString(groupActionFactoryAddress)
        );
    }
}
