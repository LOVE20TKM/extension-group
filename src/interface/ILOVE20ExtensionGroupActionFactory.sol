// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    ILOVE20ExtensionFactory
} from "@extension/src/interface/ILOVE20ExtensionFactory.sol";

/// @title ILOVE20ExtensionGroupActionFactory
/// @notice Interface for LOVE20ExtensionGroupActionFactory
interface ILOVE20ExtensionGroupActionFactory is ILOVE20ExtensionFactory {
    // ============ Events ============

    event ExtensionCreate(
        address indexed extension,
        address indexed tokenAddress
    );

    // ============ View Functions ============

    /// @notice Get the group manager address configured in the factory
    /// @return The group manager address
    function GROUP_MANAGER_ADDRESS() external view returns (address);

    /// @notice Get the group join address configured in the factory
    /// @return The group join address
    function GROUP_JOIN_ADDRESS() external view returns (address);

    /// @notice Get the group verify address configured in the factory
    /// @return The group verify address
    function GROUP_VERIFY_ADDRESS() external view returns (address);

    /// @notice Get the group address configured in the factory
    /// @return The group address
    function GROUP_ADDRESS() external view returns (address);

    /// @notice Create a new LOVE20ExtensionGroupAction extension
    /// @param tokenAddress_ The token address
    /// @param stakeTokenAddress_ The stake token address
    /// @param joinTokenAddress_ The join token address
    /// @param activationStakeAmount_ The activation stake amount
    /// @param maxJoinAmountRatio_ The max join amount ratio (with 1e18 precision)
    /// @param maxVerifyCapacityFactor_ The max verify capacity factor (with 1e18 precision)
    /// @return extension The address of the created extension
    function createExtension(
        address tokenAddress_,
        address stakeTokenAddress_,
        address joinTokenAddress_,
        uint256 activationStakeAmount_,
        uint256 maxJoinAmountRatio_,
        uint256 maxVerifyCapacityFactor_
    ) external returns (address extension);
}
