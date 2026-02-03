// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@extension/lib/core/script/BaseScript.sol";
import {GroupRecipients} from "../src/GroupRecipients.sol";

/**
 * @title DeployGroupRecipients
 * @notice Script for deploying GroupRecipients singleton contract
 * @dev Requires groupAddress from address.group.params (Group NFT contract). No separate initialize step.
 */
contract DeployGroupRecipients is BaseScript {
    address public groupRecipientsAddress;

    function run() external {
        address groupAddress = readAddressParamsFile(
            "address.group.params",
            "groupAddress"
        );
        require(
            groupAddress != address(0),
            "groupAddress not found in address.group.params"
        );

        vm.startBroadcast();
        groupRecipientsAddress = address(new GroupRecipients(groupAddress));
        vm.stopBroadcast();

        if (!hideLogs) {
            console.log("GroupRecipients deployed at:", groupRecipientsAddress);
            console.log("  GROUP_ADDRESS:", groupAddress);
        }

        updateParamsFile(
            "address.extension.group.params",
            "groupRecipientsAddress",
            vm.toString(groupRecipientsAddress)
        );
    }
}
