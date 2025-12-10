// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {LOVE20GroupDistrust} from "../src/LOVE20GroupDistrust.sol";

/**
 * @title DeployGroupDistrust
 * @notice Script for deploying LOVE20GroupDistrust singleton contract
 * @dev Requires extensionCenter, verify, and group contracts to be deployed first
 */
contract DeployGroupDistrust is BaseScript {
    address public groupDistrustAddress;

    function run() external {
        // Read addresses from params files
        address extensionCenterAddress = readAddressParamsFile(
            "address.extension.center.params",
            "extensionCenterAddress"
        );
        address verifyAddress = readAddressParamsFile(
            "address.params",
            "verifyAddress"
        );
        address groupAddress = readAddressParamsFile(
            "address.group.params",
            "groupAddress"
        );

        // Validate addresses are not zero
        require(
            extensionCenterAddress != address(0),
            "extensionCenterAddress not found in params"
        );
        require(
            verifyAddress != address(0),
            "verifyAddress not found in params"
        );
        require(groupAddress != address(0), "groupAddress not found in params");

        // Validate contracts are deployed (have code)
        require(
            extensionCenterAddress.code.length > 0,
            "extensionCenter contract not deployed"
        );
        require(verifyAddress.code.length > 0, "verify contract not deployed");
        require(groupAddress.code.length > 0, "group contract not deployed");

        vm.startBroadcast();
        groupDistrustAddress = address(
            new LOVE20GroupDistrust(
                extensionCenterAddress,
                verifyAddress,
                groupAddress
            )
        );
        vm.stopBroadcast();

        if (!hideLogs) {
            console.log(
                "LOVE20GroupDistrust deployed at:",
                groupDistrustAddress
            );
            console.log("Constructor parameters:");
            console.log("  extensionCenterAddress:", extensionCenterAddress);
            console.log("  verifyAddress:", verifyAddress);
            console.log("  groupAddress:", groupAddress);
        }

        updateParamsFile(
            "address.extension.group.params",
            "groupDistrustAddress",
            vm.toString(groupDistrustAddress)
        );
    }
}
