// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ExtensionReward} from "@extension/src/base/ExtensionReward.sol";
import {
    ILOVE20ExtensionGroupAction
} from "./interface/ILOVE20ExtensionGroupAction.sol";
import {
    ILOVE20ExtensionGroupActionFactory
} from "./interface/ILOVE20ExtensionGroupActionFactory.sol";
import {IGroupJoin} from "./interface/IGroupJoin.sol";
import {IGroupVerify} from "./interface/IGroupVerify.sol";
import {IGroupManager} from "./interface/IGroupManager.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {
    ILOVE20ExtensionFactory,
    DEFAULT_JOIN_AMOUNT
} from "@extension/src/interface/ILOVE20ExtensionFactory.sol";
import {TokenConversionLib} from "./lib/TokenConversionLib.sol";

/// @title LOVE20ExtensionGroupAction
/// @notice Extension contract for manual scoring verification in group-based actions
/// @dev Only implements GroupMint functionality, join/verify are in singleton contracts
contract LOVE20ExtensionGroupAction is
    ExtensionReward,
    ILOVE20ExtensionGroupAction
{
    // ============ Immutables ============

    IGroupJoin internal immutable _groupJoin;
    IGroupVerify internal immutable _groupVerify;
    IGroupManager internal immutable _groupManager;
    // Note: _join and _verify are inherited from ExtensionCore via ExtensionReward

    // ============ Config Immutables ============

    address public immutable override STAKE_TOKEN_ADDRESS;
    address public immutable override JOIN_TOKEN_ADDRESS;
    uint256 public immutable override ACTIVATION_STAKE_AMOUNT;
    uint256 public immutable override MAX_JOIN_AMOUNT_RATIO;
    uint256 public immutable override MAX_VERIFY_CAPACITY_FACTOR;

    // ============ State ============

    /// @dev round => burned amount
    mapping(uint256 => uint256) internal _burnedReward;

    // ============ Constructor ============

    constructor(
        address factory_,
        address tokenAddress_,
        address, // groupManagerAddress_ (unused, retrieved from factory)
        address stakeTokenAddress_,
        address joinTokenAddress_,
        uint256 activationStakeAmount_,
        uint256 maxJoinAmountRatio_,
        uint256 maxVerifyCapacityFactor_
    ) ExtensionReward(factory_, tokenAddress_) {
        ILOVE20ExtensionGroupActionFactory factory = ILOVE20ExtensionGroupActionFactory(
                factory_
            );
        address groupJoinAddress = factory.GROUP_JOIN_ADDRESS();
        _groupJoin = IGroupJoin(groupJoinAddress);
        _groupVerify = IGroupVerify(factory.GROUP_VERIFY_ADDRESS());
        _groupManager = IGroupManager(factory.GROUP_MANAGER_ADDRESS());
        // Note: _join and _verify are already initialized in ExtensionCore

        // Set GroupJoin as delegate so it can call addAccount/removeAccount on behalf of this extension
        _center.setExtensionDelegate(groupJoinAddress);

        // Store config as immutable
        STAKE_TOKEN_ADDRESS = stakeTokenAddress_;
        JOIN_TOKEN_ADDRESS = joinTokenAddress_;
        ACTIVATION_STAKE_AMOUNT = activationStakeAmount_;
        MAX_JOIN_AMOUNT_RATIO = maxJoinAmountRatio_;
        MAX_VERIFY_CAPACITY_FACTOR = maxVerifyCapacityFactor_;

        _validateJoinToken(joinTokenAddress_, tokenAddress_);
    }

    // ============ Initialization ============

    /// @notice Initialize action by joining through LOVE20Join
    /// @dev Called by GroupManager when first group is activated
    function initializeAction() external {
        if (initialized) return;

        // Auto-initialize by scanning voted actions to find matching actionId
        // This will find the actionId, approve tokens, and join
        _autoInitialize();
    }

    // ============ Reward Functions ============

    /// @notice Burn unclaimed reward when no group submitted verification in a round
    function burnUnclaimedReward(uint256 round) external override {
        if (round >= _verify.currentRound()) revert RoundNotFinished();

        uint256[] memory verifiedGroupIds = _groupVerify.verifiedGroupIds(
            tokenAddress,
            actionId,
            round
        );
        if (verifiedGroupIds.length > 0) {
            revert RoundHasVerifiedGroups();
        }

        _prepareRewardIfNeeded(round);

        uint256 rewardAmount = _reward[round];
        if (rewardAmount > 0 && _burnedReward[round] == 0) {
            _burnedReward[round] = rewardAmount;
            ILOVE20Token(tokenAddress).burn(rewardAmount);
            emit UnclaimedRewardBurn(
                tokenAddress,
                round,
                actionId,
                rewardAmount
            );
        }
    }

    /// @notice Get generated reward for a group in a round
    function generatedRewardByGroupId(
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        return _calculateRewardByGroupId(round, groupId);
    }

    /// @notice Get generated reward for a verifier in a round
    function generatedRewardByVerifier(
        uint256 round,
        address verifier
    ) external view override returns (uint256 amount) {
        uint256[] memory groupIds = _groupVerify.groupIdsByVerifier(
            tokenAddress,
            actionId,
            round,
            verifier
        );
        for (uint256 i = 0; i < groupIds.length; i++) {
            amount += _calculateRewardByGroupId(round, groupIds[i]);
        }
    }

    // ============ IExtensionJoinedValue Implementation ============

    function isJoinedValueCalculated() external view returns (bool) {
        return JOIN_TOKEN_ADDRESS != tokenAddress;
    }

    function joinedValue() external view returns (uint256) {
        uint256 totalAmount = _groupJoin.totalJoinedAmount(
            tokenAddress,
            actionId
        );
        return _convertToTokenValue(totalAmount);
    }

    function joinedValueByAccount(
        address account
    ) external view returns (uint256) {
        (, uint256 amount, ) = _groupJoin.joinInfo(
            tokenAddress,
            actionId,
            account
        );
        return _convertToTokenValue(amount);
    }

    // ============ Internal Functions ============

    /// @dev Calculate reward for an account in a specific round
    function _calculateReward(
        uint256 round,
        address account
    ) internal view override returns (uint256) {
        uint256 accountScore = _groupVerify.scoreByAccount(
            tokenAddress,
            actionId,
            round,
            account
        );
        if (accountScore == 0) return 0;

        uint256 groupId = _groupJoin.groupIdByAccountByRound(
            tokenAddress,
            actionId,
            account,
            round
        );
        if (groupId == 0) return 0;

        uint256 groupReward = _calculateRewardByGroupId(round, groupId);
        if (groupReward == 0) return 0;

        uint256 groupTotalScore = _groupVerify.totalScoreByGroupId(
            tokenAddress,
            actionId,
            round,
            groupId
        );
        if (groupTotalScore == 0) return 0;

        return (groupReward * accountScore) / groupTotalScore;
    }

    function _calculateRewardByGroupId(
        uint256 round,
        uint256 groupId
    ) internal view returns (uint256) {
        uint256 totalReward = reward(round);
        if (totalReward == 0) return 0;

        uint256 totalScore = _groupVerify.score(tokenAddress, actionId, round);
        if (totalScore == 0) return 0;

        uint256 groupScore = _groupVerify.scoreByGroupId(
            tokenAddress,
            actionId,
            round,
            groupId
        );
        return (totalReward * groupScore) / totalScore;
    }

    /// @dev Convert joinToken amount to tokenAddress value
    function _convertToTokenValue(
        uint256 amount
    ) internal view returns (uint256) {
        if (amount == 0) return 0;
        if (JOIN_TOKEN_ADDRESS == tokenAddress) return amount;
        return
            TokenConversionLib.convertLPToTokenValue(
                JOIN_TOKEN_ADDRESS,
                amount,
                tokenAddress
            );
    }

    /// @dev Validate joinToken: must be tokenAddress or LP containing tokenAddress
    function _validateJoinToken(
        address joinTokenAddress_,
        address tokenAddress_
    ) private view {
        if (joinTokenAddress_ == tokenAddress_) return;

        // Must be LP token containing tokenAddress
        if (
            !TokenConversionLib.isLPTokenContainingTarget(
                joinTokenAddress_,
                tokenAddress_
            )
        ) {
            revert IGroupJoin.InvalidJoinTokenAddress();
        }
    }
}
