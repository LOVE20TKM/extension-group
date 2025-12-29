// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {
    LOVE20ExtensionGroupActionFactory
} from "../src/LOVE20ExtensionGroupActionFactory.sol";

/**
 * @title DeployGroupActionFactory
 * @notice Script for deploying LOVE20ExtensionGroupActionFactory contract
 * @dev Requires extensionCenter, GroupManager, GroupJoin, GroupVerify contracts to be deployed first
 * @dev Note: Singletons should be initialized separately using 05_initialize_singletons.sh after deployment
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
        address groupJoinAddress = readAddressParamsFile(
            "address.extension.group.params",
            "groupJoinAddress"
        );
        address groupVerifyAddress = readAddressParamsFile(
            "address.extension.group.params",
            "groupVerifyAddress"
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
            groupJoinAddress != address(0),
            "groupJoinAddress not found in params"
        );
        require(
            groupVerifyAddress != address(0),
            "groupVerifyAddress not found in params"
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
            groupJoinAddress.code.length > 0,
            "GroupJoin contract not deployed"
        );
        require(
            groupVerifyAddress.code.length > 0,
            "GroupVerify contract not deployed"
        );

        // Read group address
        address groupAddress = readAddressParamsFile(
            "address.group.params",
            "groupAddress"
        );
        require(groupAddress != address(0), "groupAddress not found in params");
        require(groupAddress.code.length > 0, "group contract not deployed");

        vm.startBroadcast();
        groupActionFactoryAddress = address(
            new LOVE20ExtensionGroupActionFactory(
                centerAddress,
                groupManagerAddress,
                groupJoinAddress,
                groupVerifyAddress,
                groupAddress
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
            console.log("  groupJoinAddress:", groupJoinAddress);
            console.log("  groupVerifyAddress:", groupVerifyAddress);
        }

        updateParamsFile(
            "address.extension.group.params",
            "groupActionFactoryAddress",
            vm.toString(groupActionFactoryAddress)
        );
    }
}
