// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupAction} from "./interface/IGroupAction.sol";
import {IGroupActionFactory} from "./interface/IGroupActionFactory.sol";
import {IGroupJoin} from "./interface/IGroupJoin.sol";
import {IGroupJoinErrors} from "./interface/IGroupJoin.sol";
import {IGroupVerify} from "./interface/IGroupVerify.sol";
import {IGroupManager} from "./interface/IGroupManager.sol";
import {TokenConversionLib} from "./lib/TokenConversionLib.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {ExtensionBaseReward} from "@extension/src/ExtensionBaseReward.sol";
import {ExtensionBase} from "@extension/src/ExtensionBase.sol";

contract ExtensionGroupAction is ExtensionBaseReward, IGroupAction {
    IGroupJoin internal immutable _groupJoin;
    IGroupVerify internal immutable _groupVerify;
    IGroupManager internal immutable _groupManager;

    address public immutable JOIN_TOKEN_ADDRESS;
    uint256 public immutable ACTIVATION_STAKE_AMOUNT;
    uint256 public immutable MAX_JOIN_AMOUNT_RATIO;
    uint256 public immutable MAX_VERIFY_CAPACITY_FACTOR;

    // round => burned amount
    mapping(uint256 => uint256) internal _burnedReward;

    constructor(
        address factory_,
        address tokenAddress_,
        address joinTokenAddress_,
        uint256 activationStakeAmount_,
        uint256 maxJoinAmountRatio_,
        uint256 maxVerifyCapacityFactor_
    ) ExtensionBaseReward(factory_, tokenAddress_) {
        IGroupActionFactory factory = IGroupActionFactory(factory_);
        address groupJoinAddress = factory.GROUP_JOIN_ADDRESS();
        _groupJoin = IGroupJoin(groupJoinAddress);
        _groupVerify = IGroupVerify(factory.GROUP_VERIFY_ADDRESS());
        _groupManager = IGroupManager(factory.GROUP_MANAGER_ADDRESS());
        _center.setExtensionDelegate(groupJoinAddress);

        JOIN_TOKEN_ADDRESS = joinTokenAddress_;
        ACTIVATION_STAKE_AMOUNT = activationStakeAmount_;
        MAX_JOIN_AMOUNT_RATIO = maxJoinAmountRatio_;
        MAX_VERIFY_CAPACITY_FACTOR = maxVerifyCapacityFactor_;
        _validateJoinToken(joinTokenAddress_);
    }

    function burnUnclaimedReward(uint256 round) external override {
        uint256 currentRound = _verify.currentRound();
        if (round >= currentRound) revert RoundNotFinished(currentRound);
        if (_burnedReward[round] > 0) return; // Check early to avoid unnecessary mint

        uint256[] memory verifiedGroupIds = _groupVerify.verifiedGroupIds(
            address(this),
            round
        );
        if (verifiedGroupIds.length > 0) {
            revert RoundHasVerifiedGroups();
        }

        _prepareRewardIfNeeded(round);

        uint256 rewardAmount = _reward[round];
        if (rewardAmount == 0) return;

        _burnedReward[round] = rewardAmount;
        ILOVE20Token(TOKEN_ADDRESS).burn(rewardAmount);
        emit BurnUnclaimedReward({
            tokenAddress: TOKEN_ADDRESS,
            round: round,
            actionId: actionId,
            amount: rewardAmount
        });
    }

    function generatedRewardByGroupId(
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        return _calculateRewardByGroupId(round, groupId);
    }

    function generatedActionRewardByVerifier(
        uint256 round,
        address verifier
    ) external view override returns (uint256 amount) {
        uint256[] memory groupIds = _groupVerify.groupIdsByVerifier(
            address(this),
            round,
            verifier
        );
        for (uint256 i = 0; i < groupIds.length; i++) {
            amount += _calculateRewardByGroupId(round, groupIds[i]);
        }
        return amount;
    }

    function joinedAmount()
        external
        view
        override(ExtensionBase)
        returns (uint256)
    {
        return _groupJoin.joinedAmount(address(this));
    }

    function joinedAmountByAccount(
        address account
    ) external view override(ExtensionBase) returns (uint256) {
        (, uint256 amount, , ) = _groupJoin.joinInfo(address(this), account);
        return amount;
    }

    function joinedAmountTokenAddress()
        external
        view
        override(ExtensionBase)
        returns (address)
    {
        return JOIN_TOKEN_ADDRESS;
    }

    function _calculateReward(
        uint256 round,
        address account
    ) internal view override returns (uint256) {
        uint256 groupId = _groupJoin.groupIdByAccountByRound(
            address(this),
            round,
            account
        );
        if (groupId == 0) return 0;

        uint256 accountScore = _groupVerify.accountScore(
            address(this),
            round,
            account
        );
        if (accountScore == 0) return 0;

        uint256 groupTotalScore = _groupVerify.totalAccountScore(
            address(this),
            round,
            groupId
        );
        if (groupTotalScore == 0) return 0;

        uint256 groupReward = _calculateRewardByGroupId(round, groupId);
        if (groupReward == 0) return 0;

        return (groupReward * accountScore) / groupTotalScore;
    }

    function _calculateRewardByGroupId(
        uint256 round,
        uint256 groupId
    ) internal view returns (uint256) {
        uint256 totalReward = reward(round);
        if (totalReward == 0) return 0;

        uint256 totalScore = _groupVerify.totalGroupScore(address(this), round);
        if (totalScore == 0) return 0;

        uint256 groupScore = _groupVerify.groupScore(
            address(this),
            round,
            groupId
        );
        return (totalReward * groupScore) / totalScore;
    }

    function _validateJoinToken(address joinTokenAddress_) private view {
        if (joinTokenAddress_ == TOKEN_ADDRESS) return;

        if (
            !TokenConversionLib.isLPTokenContainingTarget(
                joinTokenAddress_,
                TOKEN_ADDRESS
            )
        ) {
            revert IGroupJoinErrors.InvalidJoinTokenAddress();
        }
    }
}
