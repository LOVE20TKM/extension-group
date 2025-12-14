// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {
    LOVE20ExtensionGroupActionFactory
} from "../src/LOVE20ExtensionGroupActionFactory.sol";

/**
 * @title DeployGroupActionFactory
 * @notice Script for deploying LOVE20ExtensionGroupActionFactory contract
 * @dev Requires extensionCenter contract to be deployed first
 */
contract DeployGroupActionFactory is BaseScript {
    address public groupActionFactoryAddress;

    function run() external {
        // Read address from params file
        address centerAddress = readAddressParamsFile(
            "address.extension.center.params",
            "centerAddress"
        );

        // Validate address is not zero
        require(
            centerAddress != address(0),
            "centerAddress not found in params"
        );

        // Validate contract is deployed (has code)
        require(
            centerAddress.code.length > 0,
            "extensionCenter contract not deployed"
        );

        vm.startBroadcast();
        groupActionFactoryAddress = address(
            new LOVE20ExtensionGroupActionFactory(centerAddress)
        );
        vm.stopBroadcast();

        if (!hideLogs) {
            console.log(
                "LOVE20ExtensionGroupActionFactory deployed at:",
                groupActionFactoryAddress
            );
            console.log("Constructor parameters:");
            console.log("  centerAddress:", centerAddress);
        }

        updateParamsFile(
            "address.extension.group.params",
            "groupActionFactoryAddress",
            vm.toString(groupActionFactoryAddress)
        );
    }
}
