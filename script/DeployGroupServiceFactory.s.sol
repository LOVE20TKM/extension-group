// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {
    LOVE20ExtensionGroupServiceFactory
} from "../src/LOVE20ExtensionGroupServiceFactory.sol";

/**
 * @title DeployGroupServiceFactory
 * @notice Script for deploying LOVE20ExtensionGroupServiceFactory contract
 * @dev Reads extensionCenterAddress from params and writes deployed address to address.extension.group.params
 */
contract DeployGroupServiceFactory is BaseScript {
    address public groupServiceFactoryAddress;

    function run() external {
        address extensionCenterAddress = readAddressParamsFile(
            "address.extension.center.params",
            "extensionCenterAddress"
        );
        require(
            extensionCenterAddress != address(0),
            "extensionCenterAddress not found"
        );

        vm.startBroadcast();
        groupServiceFactoryAddress = address(
            new LOVE20ExtensionGroupServiceFactory(extensionCenterAddress)
        );
        vm.stopBroadcast();

        if (!hideLogs) {
            console.log(
                "LOVE20ExtensionGroupServiceFactory deployed at:",
                groupServiceFactoryAddress
            );
            console.log("Constructor parameters:");
            console.log("  extensionCenterAddress:", extensionCenterAddress);
        }

        updateParamsFile(
            "address.extension.group.params",
            "groupServiceFactoryAddress",
            vm.toString(groupServiceFactoryAddress)
        );
    }
}
