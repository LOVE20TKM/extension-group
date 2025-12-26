// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    ILOVE20ExtensionFactory
} from "@extension/src/interface/ILOVE20ExtensionFactory.sol";

/// @title ILOVE20ExtensionGroupActionFactory
/// @notice Interface for LOVE20ExtensionGroupActionFactory
interface ILOVE20ExtensionGroupActionFactory is ILOVE20ExtensionFactory {
    // ============ Structs ============

    struct ExtensionParams {
        address tokenAddress;
        address groupManagerAddress;
        address groupDistrustAddress;
        address stakeTokenAddress;
        address joinTokenAddress;
        uint256 activationStakeAmount;
        uint256 maxJoinAmountMultiplier;
        uint256 verifyCapacityMultiplier;
    }

    // ============ Events ============

    event ExtensionCreate(
        address indexed extension,
        address indexed tokenAddress,
        address groupManagerAddress,
        address groupDistrustAddress,
        address stakeTokenAddress,
        address joinTokenAddress,
        uint256 activationStakeAmount,
        uint256 maxJoinAmountMultiplier,
        uint256 verifyCapacityMultiplier
    );

    // ============ View Functions ============

    /// @notice Get the group manager address configured in the factory
    /// @return The group manager address
    function GROUP_MANAGER_ADDRESS() external view returns (address);

    /// @notice Get the group distrust address configured in the factory
    /// @return The group distrust address
    function GROUP_DISTRUST_ADDRESS() external view returns (address);

    /// @notice Create a new LOVE20ExtensionGroupAction extension
    /// @param tokenAddress_ The token address
    /// @param stakeTokenAddress_ The stake token address
    /// @param joinTokenAddress_ The join token address
    /// @param activationStakeAmount_ The activation stake amount
    /// @param maxJoinAmountMultiplier_ The max join amount multiplier
    /// @param verifyCapacityMultiplier_ The verify capacity multiplier
    /// @return extension The address of the created extension
    function createExtension(
        address tokenAddress_,
        address stakeTokenAddress_,
        address joinTokenAddress_,
        uint256 activationStakeAmount_,
        uint256 maxJoinAmountMultiplier_,
        uint256 verifyCapacityMultiplier_
    ) external returns (address extension);

    /// @notice Get the parameters of an extension
    /// @param extension_ The extension address
    /// @return tokenAddress The token address
    /// @return groupManagerAddress The group manager address
    /// @return groupDistrustAddress The group distrust address
    /// @return stakeTokenAddress The stake token address
    /// @return joinTokenAddress The join token address
    /// @return activationStakeAmount The activation stake amount
    /// @return maxJoinAmountMultiplier The max join amount multiplier
    /// @return verifyCapacityMultiplier The verify capacity multiplier
    function extensionParams(
        address extension_
    )
        external
        view
        returns (
            address tokenAddress,
            address groupManagerAddress,
            address groupDistrustAddress,
            address stakeTokenAddress,
            address joinTokenAddress,
            uint256 activationStakeAmount,
            uint256 maxJoinAmountMultiplier,
            uint256 verifyCapacityMultiplier
        );
}
