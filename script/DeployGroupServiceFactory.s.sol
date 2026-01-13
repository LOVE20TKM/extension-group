// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {
    ExtensionGroupServiceFactory
} from "../src/ExtensionGroupServiceFactory.sol";

/**
 * @title DeployGroupServiceFactory
 * @notice Script for deploying ExtensionGroupServiceFactory contract
 * @dev Requires extensionCenter contract to be deployed first
 */
contract DeployGroupServiceFactory is BaseScript {
    address public groupServiceFactoryAddress;

    function run() external {
        // Read groupActionFactoryAddress from params file
        address groupActionFactoryAddress = readAddressParamsFile(
            "address.extension.group.params",
            "groupActionFactoryAddress"
        );

        // Validate address is not zero
        require(
            groupActionFactoryAddress != address(0),
            "groupActionFactoryAddress not found in params"
        );

        // Validate contract is deployed (has code)
        require(
            groupActionFactoryAddress.code.length > 0,
            "groupActionFactory contract not deployed"
        );

        vm.startBroadcast();
        groupServiceFactoryAddress = address(
            new ExtensionGroupServiceFactory(groupActionFactoryAddress)
        );
        vm.stopBroadcast();

        if (!hideLogs) {
            console.log(
                "ExtensionGroupServiceFactory deployed at:",
                groupServiceFactoryAddress
            );
            console.log("Constructor parameters:");
            console.log(
                "  groupActionFactoryAddress:",
                groupActionFactoryAddress
            );
        }

        updateParamsFile(
            "address.extension.group.params",
            "groupServiceFactoryAddress",
            vm.toString(groupServiceFactoryAddress)
        );
    }
}
