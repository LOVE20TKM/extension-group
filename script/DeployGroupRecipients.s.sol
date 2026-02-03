// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {GroupRecipients} from "../src/GroupRecipients.sol";

/**
 * @title DeployGroupRecipients
 * @notice Script for deploying GroupRecipients singleton contract
 * @dev Requires groupActionFactoryAddress from address.extension.group.params
 */
contract DeployGroupRecipients is BaseScript {
    address public groupRecipientsAddress;

    function run() external {
        address groupActionFactoryAddress = readAddressParamsFile(
            "address.extension.group.params",
            "groupActionFactoryAddress"
        );
        require(
            groupActionFactoryAddress != address(0),
            "groupActionFactoryAddress not found in address.extension.group.params"
        );

        vm.startBroadcast();
        groupRecipientsAddress = address(
            new GroupRecipients(groupActionFactoryAddress)
        );
        vm.stopBroadcast();

        if (!hideLogs) {
            console.log("GroupRecipients deployed at:", groupRecipientsAddress);
            console.log(
                "  groupActionFactoryAddress:",
                groupActionFactoryAddress
            );
        }

        updateParamsFile(
            "address.extension.group.params",
            "groupRecipientsAddress",
            vm.toString(groupRecipientsAddress)
        );
    }
}
