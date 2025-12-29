// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {GroupJoin} from "../src/GroupJoin.sol";

/**
 * @title DeployGroupJoin
 * @notice Script for deploying GroupJoin singleton contract
 */
contract DeployGroupJoin is BaseScript {
    address public groupJoinAddress;

    function run() external {
        vm.startBroadcast();
        groupJoinAddress = address(new GroupJoin());
        vm.stopBroadcast();

        if (!hideLogs) {
            console.log("GroupJoin deployed at:", groupJoinAddress);
        }

        updateParamsFile(
            "address.extension.group.params",
            "groupJoinAddress",
            vm.toString(groupJoinAddress)
        );
    }
}

