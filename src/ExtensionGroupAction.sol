// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ExtensionBase} from "@extension/src/ExtensionBase.sol";
import {ExtensionCore} from "@extension/src/ExtensionCore.sol";
import {IExtensionCore} from "@extension/src/interface/IExtensionCore.sol";
import {IExtensionGroupAction} from "./interface/IExtensionGroupAction.sol";
import {
    IExtensionGroupActionFactory
} from "./interface/IExtensionGroupActionFactory.sol";
import {IGroupJoin} from "./interface/IGroupJoin.sol";
import {IGroupVerify} from "./interface/IGroupVerify.sol";
import {IGroupManager} from "./interface/IGroupManager.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {
    IExtensionFactory,
    DEFAULT_JOIN_AMOUNT
} from "@extension/src/interface/IExtensionFactory.sol";
import {TokenConversionLib} from "./lib/TokenConversionLib.sol";

contract ExtensionGroupAction is ExtensionBase, IExtensionGroupAction {
    IGroupJoin internal immutable _groupJoin;
    IGroupVerify internal immutable _groupVerify;
    IGroupManager internal immutable _groupManager;

    address public immutable STAKE_TOKEN_ADDRESS;
    address public immutable JOIN_TOKEN_ADDRESS;
    uint256 public immutable ACTIVATION_STAKE_AMOUNT;
    uint256 public immutable MAX_JOIN_AMOUNT_RATIO;
    uint256 public immutable MAX_VERIFY_CAPACITY_FACTOR;

    // round => burned amount
    mapping(uint256 => uint256) internal _burnedReward;

    constructor(
        address factory_,
        address tokenAddress_,
        address stakeTokenAddress_,
        address joinTokenAddress_,
        uint256 activationStakeAmount_,
        uint256 maxJoinAmountRatio_,
        uint256 maxVerifyCapacityFactor_
    ) ExtensionBase(factory_, tokenAddress_) {
        IExtensionGroupActionFactory factory = IExtensionGroupActionFactory(
            factory_
        );
        address groupJoinAddress = factory.GROUP_JOIN_ADDRESS();
        _groupJoin = IGroupJoin(groupJoinAddress);
        _groupVerify = IGroupVerify(factory.GROUP_VERIFY_ADDRESS());
        _groupManager = IGroupManager(factory.GROUP_MANAGER_ADDRESS());
        _center.setExtensionDelegate(groupJoinAddress);

        STAKE_TOKEN_ADDRESS = stakeTokenAddress_;
        JOIN_TOKEN_ADDRESS = joinTokenAddress_;
        ACTIVATION_STAKE_AMOUNT = activationStakeAmount_;
        MAX_JOIN_AMOUNT_RATIO = maxJoinAmountRatio_;
        MAX_VERIFY_CAPACITY_FACTOR = maxVerifyCapacityFactor_;

        _validateJoinToken(joinTokenAddress_, tokenAddress_);
    }

    function burnUnclaimedReward(uint256 round) external override {
        if (round >= _verify.currentRound()) revert RoundNotFinished();

        uint256[] memory verifiedGroupIds = _groupVerify.verifiedGroupIds(
            address(this),
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

    function generatedRewardByGroupId(
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        return _calculateRewardByGroupId(round, groupId);
    }

    function generatedRewardByVerifier(
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
    }

    function isJoinedValueConverted()
        external
        view
        override(ExtensionCore, IExtensionCore)
        returns (bool)
    {
        return JOIN_TOKEN_ADDRESS != tokenAddress;
    }

    function joinedValue()
        external
        view
        override(ExtensionCore, IExtensionCore)
        returns (uint256)
    {
        uint256 totalAmount = _groupJoin.totalJoinedAmount(address(this));
        return _convertToTokenValue(totalAmount);
    }

    function joinedValueByAccount(
        address account
    ) external view override(ExtensionCore, IExtensionCore) returns (uint256) {
        (, uint256 amount, ) = _groupJoin.joinInfo(address(this), account);
        return _convertToTokenValue(amount);
    }

    function _calculateReward(
        uint256 round,
        address account
    ) internal view override returns (uint256) {
        uint256 accountScore = _groupVerify.scoreByAccount(
            address(this),
            round,
            account
        );
        if (accountScore == 0) return 0;

        uint256 groupId = _groupJoin.groupIdByAccountByRound(
            address(this),
            account,
            round
        );
        if (groupId == 0) return 0;

        uint256 groupReward = _calculateRewardByGroupId(round, groupId);
        if (groupReward == 0) return 0;

        uint256 groupTotalScore = _groupVerify.totalScoreByGroupId(
            address(this),
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

        uint256 totalScore = _groupVerify.score(address(this), round);
        if (totalScore == 0) return 0;

        uint256 groupScore = _groupVerify.scoreByGroupId(
            address(this),
            round,
            groupId
        );
        return (totalReward * groupScore) / totalScore;
    }

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

    function _validateJoinToken(
        address joinTokenAddress_,
        address tokenAddress_
    ) private view {
        if (joinTokenAddress_ == tokenAddress_) return;

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
