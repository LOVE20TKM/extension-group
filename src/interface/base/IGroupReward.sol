// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/// @title IGroupReward
/// @notice Interface for group reward queries
interface IGroupReward {
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
}
