// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {
    ExtensionGroupServiceFactory
} from "../src/ExtensionGroupServiceFactory.sol";

/**
 * @title DeployGroupServiceFactory
 * @notice Script for deploying ExtensionGroupServiceFactory
 * @dev Requires GroupRecipients and ExtensionGroupActionFactory to be deployed first (params). GroupRecipients takes groupAddress in constructor at deploy time.
 */
contract DeployGroupServiceFactory is BaseScript {
    address public groupServiceFactoryAddress;

    function run() external {
        address groupActionFactoryAddress = readAddressParamsFile(
            "address.extension.group.params",
            "groupActionFactoryAddress"
        );
        address groupRecipientsAddress = readAddressParamsFile(
            "address.extension.group.params",
            "groupRecipientsAddress"
        );

        require(
            groupActionFactoryAddress != address(0),
            "groupActionFactoryAddress not found in params"
        );
        require(
            groupActionFactoryAddress.code.length > 0,
            "groupActionFactory contract not deployed"
        );
        require(
            groupRecipientsAddress != address(0),
            "groupRecipientsAddress not found in params"
        );
        require(
            groupRecipientsAddress.code.length > 0,
            "groupRecipients contract not deployed"
        );

        vm.startBroadcast();
        groupServiceFactoryAddress = address(
            new ExtensionGroupServiceFactory(
                groupActionFactoryAddress,
                groupRecipientsAddress
            )
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
            console.log("  groupRecipients:", groupRecipientsAddress);
        }

        updateParamsFile(
            "address.extension.group.params",
            "groupServiceFactoryAddress",
            vm.toString(groupServiceFactoryAddress)
        );
    }
}
