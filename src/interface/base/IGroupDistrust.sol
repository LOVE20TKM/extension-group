// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/// @title IGroupDistrust
/// @notice Interface for distrust voting on GroupAction
/// @dev All view functions are in ILOVE20GroupDistrust, query directly there
interface IGroupDistrust {
    // ============ Write Functions ============

    function distrustVote(
        address groupOwner,
        uint256 amount,
        string calldata reason
    ) external;
}
