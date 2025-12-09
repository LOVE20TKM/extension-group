// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {
    LOVE20ExtensionGroupActionFactory
} from "../src/LOVE20ExtensionGroupActionFactory.sol";

/**
 * @title DeployGroupActionFactory
 * @notice Script for deploying LOVE20ExtensionGroupActionFactory contract
 * @dev Reads extensionCenterAddress from params and writes deployed address to address.extension.group.params
 */
contract DeployGroupActionFactory is BaseScript {
    address public groupActionFactoryAddress;

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
        groupActionFactoryAddress = address(
            new LOVE20ExtensionGroupActionFactory(extensionCenterAddress)
        );
        vm.stopBroadcast();

        if (!hideLogs) {
            console.log(
                "LOVE20ExtensionGroupActionFactory deployed at:",
                groupActionFactoryAddress
            );
            console.log("Constructor parameters:");
            console.log("  extensionCenterAddress:", extensionCenterAddress);
        }

        updateParamsFile(
            "address.extension.group.params",
            "groupActionFactoryAddress",
            vm.toString(groupActionFactoryAddress)
        );
    }
}
