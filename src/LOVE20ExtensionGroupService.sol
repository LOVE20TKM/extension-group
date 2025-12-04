// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ExtensionCore} from "@extension/src/base/ExtensionCore.sol";
import {ExtensionAccounts} from "@extension/src/base/ExtensionAccounts.sol";
import {
    ExtensionVerificationInfo
} from "@extension/src/base/ExtensionVerificationInfo.sol";
import {ILOVE20Extension} from "@extension/src/interface/ILOVE20Extension.sol";
import {IExtensionExit} from "@extension/src/interface/base/IExtensionExit.sol";
import {
    IExtensionReward
} from "@extension/src/interface/base/IExtensionReward.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {
    ILOVE20ExtensionGroupAction
} from "./interface/ILOVE20ExtensionGroupAction.sol";
import {
    EnumerableSet
} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title LOVE20ExtensionGroupService
/// @notice Extension contract for rewarding group service providers
/// @dev Service reward = Total service reward × (Account's group action reward / Group action total reward)
contract LOVE20ExtensionGroupService is
    ExtensionAccounts,
    ExtensionVerificationInfo,
    ILOVE20Extension
{
    using EnumerableSet for EnumerableSet.AddressSet;

    // ============ Errors ============

    error NoActiveGroups();
    error AlreadyJoined();

    // ============ Events ============

    event Join(address indexed account, uint256 joinedValue, uint256 round);
    event Exit(address indexed account, uint256 round);

    // ============ Immutables ============

    address public immutable GROUP_ACTION_ADDRESS;

    // ============ State ============

    /// @dev round => total reward for the round
    mapping(uint256 => uint256) internal _reward;

    /// @dev round => account => claimed reward
    mapping(uint256 => mapping(address => uint256)) internal _claimedReward;

    // ============ Constructor ============

    constructor(
        address factory_,
        address tokenAddress_,
        address groupActionAddress_
    ) ExtensionCore(factory_, tokenAddress_) {
        GROUP_ACTION_ADDRESS = groupActionAddress_;
    }

    // ============ Write Functions ============

    /// @notice Join the service reward action
    function join() external {
        _autoInitialize();

        if (_accounts.contains(msg.sender)) revert AlreadyJoined();

        uint256 stakedAmount = ILOVE20ExtensionGroupAction(GROUP_ACTION_ADDRESS)
            .totalStakedByOwner(msg.sender);
        if (stakedAmount == 0) revert NoActiveGroups();

        _addAccount(msg.sender);

        emit Join(msg.sender, stakedAmount, _join.currentRound());
    }

    /// @inheritdoc IExtensionExit
    function exit() external {
        _removeAccount(msg.sender);
        emit Exit(msg.sender, _join.currentRound());
    }

    // ============ IExtensionJoinedValue Implementation ============

    function isJoinedValueCalculated() external pure returns (bool) {
        return false;
    }

    function joinedValue() external view returns (uint256) {
        return ILOVE20ExtensionGroupAction(GROUP_ACTION_ADDRESS).totalStaked();
    }

    function joinedValueByAccount(
        address account
    ) external view returns (uint256) {
        if (!_accounts.contains(account)) return 0;
        return
            ILOVE20ExtensionGroupAction(GROUP_ACTION_ADDRESS)
                .totalStakedByOwner(account);
    }

    // ============ IExtensionReward Implementation ============

    /// @inheritdoc IExtensionReward
    function rewardByAccount(
        uint256 round,
        address account
    ) public view returns (uint256 amount, bool isMinted) {
        uint256 claimed = _claimedReward[round][account];
        if (claimed > 0) {
            return (claimed, true);
        }
        return (_calculateReward(round, account), false);
    }

    /// @inheritdoc IExtensionReward
    function claimReward(uint256 round) external returns (uint256 amount) {
        if (round >= _verify.currentRound()) revert RoundNotFinished();

        _prepareRewardIfNeeded(round);

        bool isMinted;
        (amount, isMinted) = rewardByAccount(round, msg.sender);
        if (isMinted) revert AlreadyClaimed();

        _claimedReward[round][msg.sender] = amount;

        if (amount > 0) {
            ILOVE20Token(tokenAddress).transfer(msg.sender, amount);
        }

        emit ClaimReward(tokenAddress, msg.sender, actionId, round, amount);
    }

    /// @inheritdoc IExtensionReward
    function reward(uint256 round) external view returns (uint256) {
        return _reward[round];
    }

    // ============ Internal Functions ============

    function _prepareRewardIfNeeded(uint256 round) internal {
        if (_reward[round] > 0) return;

        uint256 totalActionReward = _mint.mintActionReward(
            tokenAddress,
            round,
            actionId
        );
        _reward[round] = totalActionReward;
    }

    function _calculateReward(
        uint256 round,
        address account
    ) internal view returns (uint256) {
        if (!_accounts.contains(account)) return 0;

        uint256 totalReward = _reward[round];
        if (totalReward == 0) return 0;

        uint256 groupActionReward = ILOVE20ExtensionGroupAction(
            GROUP_ACTION_ADDRESS
        ).rewardByGroupOwner(round, account);
        if (groupActionReward == 0) return 0;

        uint256 groupActionTotalReward = ILOVE20ExtensionGroupAction(
            GROUP_ACTION_ADDRESS
        ).reward(round);
        if (groupActionTotalReward == 0) return 0;

        return (totalReward * groupActionReward) / groupActionTotalReward;
    }
}
