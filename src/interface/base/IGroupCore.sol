// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/// @title IGroupCore
/// @notice Interface for GroupCore config getters
/// @dev View and write functions are in ILOVE20GroupManager (query GroupManager directly)
interface IGroupCore {
    // --- GroupManager Reference ---
    function GROUP_MANAGER_ADDRESS() external view returns (address);

    // --- Config Parameters ---
    function GROUP_ADDRESS() external view returns (address);
    function STAKE_TOKEN_ADDRESS() external view returns (address);
    function GROUP_ACTIVATION_STAKE_AMOUNT() external view returns (uint256);
    function MAX_JOIN_AMOUNT_MULTIPLIER() external view returns (uint256);
    function VERIFY_CAPACITY_MULTIPLIER() external view returns (uint256);
}
