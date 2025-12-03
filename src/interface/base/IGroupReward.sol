// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    IExtensionReward
} from "@extension/src/interface/base/IExtensionReward.sol";

/// @title IGroupReward
/// @notice Interface for group reward queries
interface IGroupReward is IExtensionReward {
    // ============ Errors ============

    error RoundHasVerifiedGroups();

    // ============ Events ============

    event UnclaimedRewardBurned(uint256 indexed round, uint256 amount);

    // ============ Functions ============

    /// @notice Burn unclaimed reward when no group submitted verification in a round
    function burnUnclaimedReward(uint256 round) external;

    function rewardByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function rewardByGroupOwner(
        uint256 round,
        address groupOwner
    ) external view returns (uint256);
}
