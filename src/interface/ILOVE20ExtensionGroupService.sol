// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILOVE20Extension} from "@extension/src/interface/ILOVE20Extension.sol";

/// @title ILOVE20ExtensionGroupService
/// @notice Interface for group service provider reward extension
interface ILOVE20ExtensionGroupService is ILOVE20Extension {
    // ============ Errors ============

    error NoActiveGroups();
    error AlreadyJoined();

    // ============ Events ============

    event Join(address indexed account, uint256 joinedValue, uint256 round);
    event Exit(address indexed account, uint256 round);

    // ============ View Functions ============

    function GROUP_ACTION_ADDRESS() external view returns (address);

    // ============ Write Functions ============

    function join() external;
}
