// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILOVE20Group} from "@group/interfaces/ILOVE20Group.sol";
import {ExtensionReward} from "@extension/src/base/ExtensionReward.sol";
import {IGroupCore} from "../interface/base/IGroupCore.sol";
import {ILOVE20GroupManager} from "../interface/ILOVE20GroupManager.sol";

/// @title GroupCore
/// @notice Base contract with config parameters from GroupManager
/// @dev Users call GroupManager directly for all operations
abstract contract GroupCore is ExtensionReward, IGroupCore {
    // ============ Immutables ============

    address public immutable GROUP_MANAGER_ADDRESS;
    ILOVE20GroupManager internal immutable _groupManager;

    // Config parameters (copied from GroupManager for gas efficiency)
    address public immutable GROUP_ADDRESS;
    address public immutable STAKE_TOKEN_ADDRESS;
    uint256 public immutable MIN_GOV_VOTE_RATIO_BPS;
    uint256 public immutable GROUP_ACTIVATION_STAKE_AMOUNT;
    uint256 public immutable MAX_JOIN_AMOUNT_MULTIPLIER;

    // ============ Constructor ============

    constructor(
        address factory_,
        address tokenAddress_,
        address groupManagerAddress_,
        address stakeTokenAddress_,
        uint256 minGovVoteRatioBps_,
        uint256 activationStakeAmount_,
        uint256 maxJoinAmountMultiplier_
    ) ExtensionReward(factory_, tokenAddress_) {
        GROUP_MANAGER_ADDRESS = groupManagerAddress_;
        _groupManager = ILOVE20GroupManager(groupManagerAddress_);

        // Store config locally for gas efficiency (GROUP_ADDRESS from GroupManager)
        GROUP_ADDRESS = _groupManager.GROUP_ADDRESS();
        STAKE_TOKEN_ADDRESS = stakeTokenAddress_;
        MIN_GOV_VOTE_RATIO_BPS = minGovVoteRatioBps_;
        GROUP_ACTIVATION_STAKE_AMOUNT = activationStakeAmount_;
        MAX_JOIN_AMOUNT_MULTIPLIER = maxJoinAmountMultiplier_;

        // Register config in GroupManager (msg.sender is this extension)
        _groupManager.setConfig(
            stakeTokenAddress_,
            minGovVoteRatioBps_,
            activationStakeAmount_,
            maxJoinAmountMultiplier_
        );
    }
}
