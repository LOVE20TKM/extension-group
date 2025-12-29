// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {GroupVerify} from "../src/GroupVerify.sol";

/**
 * @title DeployGroupVerify
 * @notice Script for deploying GroupVerify singleton contract
 */
contract DeployGroupVerify is BaseScript {
    address public groupVerifyAddress;

    function run() external {
        vm.startBroadcast();
        groupVerifyAddress = address(new GroupVerify());
        vm.stopBroadcast();

        if (!hideLogs) {
            console.log("GroupVerify deployed at:", groupVerifyAddress);
        }

        updateParamsFile(
            "address.extension.group.params",
            "groupVerifyAddress",
            vm.toString(groupVerifyAddress)
        );
    }
}

