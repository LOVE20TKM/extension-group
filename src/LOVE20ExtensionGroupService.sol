// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ExtensionAccounts} from "@extension/src/base/ExtensionAccounts.sol";
import {ExtensionReward} from "@extension/src/base/ExtensionReward.sol";
import {
    ExtensionVerificationInfo
} from "@extension/src/base/ExtensionVerificationInfo.sol";
import {ILOVE20Extension} from "@extension/src/interface/ILOVE20Extension.sol";
import {IExtensionExit} from "@extension/src/interface/base/IExtensionExit.sol";
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
    ExtensionReward,
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

    // ============ Constructor ============

    constructor(
        address factory_,
        address tokenAddress_,
        address groupActionAddress_
    ) ExtensionReward(factory_, tokenAddress_) {
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

    // ============ Internal Functions ============

    function _calculateReward(
        uint256 round,
        address account
    ) internal view override returns (uint256) {
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
