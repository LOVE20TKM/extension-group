// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IExtension} from "@extension/src/interface/IExtension.sol";

/// @title ILOVE20ExtensionGroupAction
/// @notice Interface for group-based action extension with manual scoring
/// @dev Join and Verify functions are in GroupJoin and GroupVerify singleton contracts
interface ILOVE20ExtensionGroupAction is IExtension{
    // ============ Errors ============

    error RoundHasVerifiedGroups();

    // ============ Events ============

    event UnclaimedRewardBurn(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 amount
    );

    // ============ Functions ============

    /// @notice Burn unclaimed reward when no group submitted verification in a round
    function burnUnclaimedReward(uint256 round) external;

    function generatedRewardByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function generatedRewardByVerifier(
        uint256 round,
        address verifier
    ) external view returns (uint256);

    // ============ Config Getters ============

    /// @notice Get stake token address
    function STAKE_TOKEN_ADDRESS() external view returns (address);

    /// @notice Get join token address
    function JOIN_TOKEN_ADDRESS() external view returns (address);

    /// @notice Get activation stake amount
    function ACTIVATION_STAKE_AMOUNT() external view returns (uint256);

    /// @notice Get max join amount ratio
    function MAX_JOIN_AMOUNT_RATIO() external view returns (uint256);

    /// @notice Get max verify capacity factor
    function MAX_VERIFY_CAPACITY_FACTOR() external view returns (uint256);
}
