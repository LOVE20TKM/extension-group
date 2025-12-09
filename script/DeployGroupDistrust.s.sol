// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {LOVE20GroupDistrust} from "../src/LOVE20GroupDistrust.sol";

/**
 * @title DeployGroupDistrust
 * @notice Script for deploying LOVE20GroupDistrust singleton contract
 */
contract DeployGroupDistrust is BaseScript {
    address public groupDistrustAddress;

    function run() external {
        address extensionCenterAddress = readAddressParamsFile(
            "address.extension.center.params",
            "extensionCenterAddress"
        );
        address verifyAddress = readAddressParamsFile(
            "address.params",
            "verifyAddress"
        );
        address groupAddress = readAddressParamsFile(
            "address.params",
            "groupAddress"
        );
        require(
            extensionCenterAddress != address(0),
            "extensionCenterAddress not found"
        );
        require(verifyAddress != address(0), "verifyAddress not found");
        require(groupAddress != address(0), "groupAddress not found");

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
