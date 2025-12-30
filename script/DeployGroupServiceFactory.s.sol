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
        // #region agent log
        string memory root = vm.projectRoot();
        string memory network = vm.envString("network");
        string memory filePath = string(
            abi.encodePacked(
                root,
                "/script/network/",
                network,
                "/address.extension.group.params"
            )
        );
        console.log("HYP_A: Reading groupActionFactoryAddress from:", filePath);
        console.log("HYP_C: File path:", filePath);
        // #endregion

        // Read groupActionFactoryAddress from params file
        address groupActionFactoryAddress = readAddressParamsFile(
            "address.extension.group.params",
            "groupActionFactoryAddress"
        );

        // #region agent log
        console.log(
            "HYP_A: groupActionFactoryAddress read:",
            groupActionFactoryAddress
        );
        console.log(
            "HYP_A: code.length before check:",
            groupActionFactoryAddress.code.length
        );
        // #endregion

        // Validate address is not zero
        require(
            groupActionFactoryAddress != address(0),
            "groupActionFactoryAddress not found in params"
        );

        // Validate contract is deployed (has code)
        // #region agent log
        uint256 codeLengthBefore = groupActionFactoryAddress.code.length;
        console.log("HYP_A: code.length check:", codeLengthBefore);
        console.log("HYP_B: About to start broadcast");
        // #endregion
        require(
            groupActionFactoryAddress.code.length > 0,
            "groupActionFactory contract not deployed"
        );

        vm.startBroadcast();
        // #region agent log
        console.log(
            "HYP_B: Starting deployment, groupActionFactoryAddress:",
            groupActionFactoryAddress
        );
        console.log(
            "HYP_B: code.length at deployment time:",
            groupActionFactoryAddress.code.length
        );
        // #endregion
        groupServiceFactoryAddress = address(
            new ExtensionGroupServiceFactory(groupActionFactoryAddress)
        );
        // #region agent log
        console.log(
            "HYP_B: Deployment completed, address:",
            groupServiceFactoryAddress
        );
        console.log(
            "HYP_B: deployed address code.length:",
            groupServiceFactoryAddress.code.length
        );
        // #endregion
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

        // #region agent log
        string memory updateFilePath = string(
            abi.encodePacked(
                root,
                "/script/network/",
                network,
                "/address.extension.group.params"
            )
        );
        console.log("HYP_C: About to update params file:", updateFilePath);
        console.log("HYP_D: Address to write:", groupServiceFactoryAddress);
        // #endregion
        updateParamsFile(
            "address.extension.group.params",
            "groupServiceFactoryAddress",
            vm.toString(groupServiceFactoryAddress)
        );
        // #region agent log
        console.log("HYP_D: updateParamsFile completed");
        // #endregion
    }
}
