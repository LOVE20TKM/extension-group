// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {GroupNotice} from "../src/GroupNotice.sol";

/**
 * @title DeployGroupNotice
 * @notice Script for deploying GroupNotice contract
 * @dev Requires groupAddress from address.group.params
 */
contract DeployGroupNotice is BaseScript {
    address public groupNoticeAddress;

    function run() external {
        address groupAddress = readAddressParamsFile(
            "address.group.params",
            "groupAddress"
        );
        require(
            groupAddress != address(0),
            "groupAddress not found in address.group.params"
        );
        require(
            groupAddress.code.length > 0,
            "Group contract not deployed"
        );

        vm.startBroadcast();
        groupNoticeAddress = address(new GroupNotice(groupAddress));
        vm.stopBroadcast();

        if (!hideLogs) {
            console.log("GroupNotice deployed at:", groupNoticeAddress);
            console.log("  groupAddress:", groupAddress);
        }

        updateParamsFile(
            "address.extension.group.params",
            "groupNoticeAddress",
            vm.toString(groupNoticeAddress)
        );
    }
}
