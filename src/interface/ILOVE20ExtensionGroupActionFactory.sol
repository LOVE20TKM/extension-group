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
