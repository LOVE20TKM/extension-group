// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupTokenJoin} from "../interface/base/IGroupTokenJoin.sol";
import {GroupCore} from "./GroupCore.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {RoundHistoryUint256} from "@extension/src/lib/RoundHistoryUint256.sol";
import {VerificationInfo} from "@extension/src/base/VerificationInfo.sol";
import {ILOVE20GroupManager} from "../interface/ILOVE20GroupManager.sol";

using RoundHistoryUint256 for RoundHistoryUint256.History;

/// @title GroupTokenJoin
/// @notice Handles token-based group joining and exiting
abstract contract GroupTokenJoin is
    GroupCore,
    ReentrancyGuard,
    VerificationInfo,
    IGroupTokenJoin
{
    // ============ Immutables ============

    address public immutable JOIN_TOKEN_ADDRESS;
    IERC20 internal immutable _joinToken;

    // Account state
    mapping(address => JoinInfo) internal _joinInfo;
    mapping(address => RoundHistoryUint256.History)
        internal _groupIdHistoryByAccount;

    // Group state (local tracking)
    mapping(uint256 => address[]) internal _accountsByGroupId;
    mapping(uint256 => mapping(address => uint256))
        internal _accountIndexInGroup;
    mapping(uint256 => RoundHistoryUint256.History)
        internal _totalJoinedAmountHistoryByGroupId;
    RoundHistoryUint256.History internal _totalJoinedAmountHistory;

    // ============ Constructor ============

    constructor(address joinTokenAddress_) {
        if (joinTokenAddress_ == address(0)) revert InvalidJoinTokenAddress();
        JOIN_TOKEN_ADDRESS = joinTokenAddress_;
        _joinToken = IERC20(joinTokenAddress_);
    }

    // ============ Write Functions ============

    function join(
        uint256 groupId,
        uint256 amount,
        string[] memory verificationInfos
    ) public virtual nonReentrant {
        _autoInitialize();

        if (amount == 0) revert JoinAmountZero();

        JoinInfo storage info = _joinInfo[msg.sender];
        bool isFirstJoin = info.groupId == 0;
        uint256 newTotal = info.amount + amount;

        // Validate group and membership in scoped block to reduce stack depth
        {
            (
                ,
                ,
                ,
                uint256 capacity,
                uint256 groupMinJoinAmount,
                uint256 groupMaxJoinAmount,
                bool isActive,
                ,

            ) = _groupManager.groupInfo(tokenAddress, actionId, groupId);

            if (!isFirstJoin && info.groupId != groupId)
                revert AlreadyInOtherGroup();
            if (!isActive) revert CannotJoinDeactivatedGroup();

            if (isFirstJoin) {
                uint256 minAmount = groupMinJoinAmount > MIN_JOIN_AMOUNT
                    ? groupMinJoinAmount
                    : MIN_JOIN_AMOUNT;
                if (amount < minAmount) revert AmountBelowMinimum();
            }

            if (groupMaxJoinAmount > 0 && newTotal > groupMaxJoinAmount) {
                revert AmountExceedsAccountCap();
            }
            if (
                newTotal >
                _groupManager.calculateJoinMaxAmount(tokenAddress, actionId)
            ) revert AmountExceedsAccountCap();

            if (
                _totalJoinedAmountHistoryByGroupId[groupId].latestValue() +
                    amount >
                capacity
            ) revert GroupCapacityFull();
        }

        // Transfer tokens and update state
        _joinToken.transferFrom(msg.sender, address(this), amount);

        uint256 currentRound = _join.currentRound();
        info.groupId = groupId;
        info.amount = newTotal;

        // Update totalJoinedAmount history
        _totalJoinedAmountHistoryByGroupId[groupId].record(
            currentRound,
            _totalJoinedAmountHistoryByGroupId[groupId].latestValue() + amount
        );
        _totalJoinedAmountHistory.record(
            currentRound,
            _totalJoinedAmountHistory.latestValue() + amount
        );

        if (isFirstJoin) {
            info.joinedRound = currentRound;
            _groupIdHistoryByAccount[msg.sender].record(currentRound, groupId);
            _addAccountToGroup(groupId, msg.sender);
            _center.addAccount(tokenAddress, actionId, msg.sender);
        }

        updateVerificationInfo(verificationInfos);

        emit Join(
            tokenAddress,
            currentRound,
            actionId,
            groupId,
            msg.sender,
            amount
        );
    }

    function exit() public virtual nonReentrant {
        JoinInfo storage info = _joinInfo[msg.sender];
        if (info.groupId == 0) revert NotInGroup();

        uint256 groupId = info.groupId;
        uint256 amount = info.amount;

        uint256 currentRound = _join.currentRound();

        // Update state
        _groupIdHistoryByAccount[msg.sender].record(currentRound, 0);

        // Update totalJoinedAmount history
        _totalJoinedAmountHistoryByGroupId[groupId].record(
            currentRound,
            _totalJoinedAmountHistoryByGroupId[groupId].latestValue() - amount
        );
        _totalJoinedAmountHistory.record(
            currentRound,
            _totalJoinedAmountHistory.latestValue() - amount
        );

        _removeAccountFromGroup(groupId, msg.sender);
        delete _joinInfo[msg.sender];
        _center.removeAccount(tokenAddress, actionId, msg.sender);

        // Transfer tokens back
        _joinToken.transfer(msg.sender, amount);

        emit Exit(
            tokenAddress,
            currentRound,
            actionId,
            groupId,
            msg.sender,
            amount
        );
    }

    // ============ View Functions ============

    function totalJoinedAmountByGroupId(
        uint256 groupId
    ) external view returns (uint256) {
        return _totalJoinedAmountHistoryByGroupId[groupId].latestValue();
    }

    function joinInfo(
        address account
    )
        external
        view
        returns (uint256 joinedRound, uint256 amount, uint256 groupId)
    {
        JoinInfo storage info = _joinInfo[account];
        return (info.joinedRound, info.amount, info.groupId);
    }

    function accountsByGroupId(
        uint256 groupId
    ) external view returns (address[] memory) {
        return _accountsByGroupId[groupId];
    }
    function accountsByGroupIdCount(
        uint256 groupId
    ) external view returns (uint256) {
        return _accountsByGroupId[groupId].length;
    }
    function accountsByGroupIdAtIndex(
        uint256 groupId,
        uint256 index
    ) external view returns (address) {
        return _accountsByGroupId[groupId][index];
    }

    function groupIdByAccountByRound(
        address account,
        uint256 round
    ) public view returns (uint256) {
        return _groupIdHistoryByAccount[account].value(round);
    }

    function totalJoinedAmountByGroupIdByRound(
        uint256 groupId,
        uint256 round
    ) public view returns (uint256) {
        return _totalJoinedAmountHistoryByGroupId[groupId].value(round);
    }

    function totalJoinedAmount() public view returns (uint256) {
        return _totalJoinedAmountHistory.latestValue();
    }

    function totalJoinedAmountByRound(
        uint256 round
    ) public view returns (uint256) {
        return _totalJoinedAmountHistory.value(round);
    }

    // ============ Internal Functions ============

    function _addAccountToGroup(uint256 groupId, address account) internal {
        _accountIndexInGroup[groupId][account] = _accountsByGroupId[groupId]
            .length;
        _accountsByGroupId[groupId].push(account);
    }

    function _removeAccountFromGroup(
        uint256 groupId,
        address account
    ) internal {
        address[] storage accounts = _accountsByGroupId[groupId];
        uint256 index = _accountIndexInGroup[groupId][account];
        uint256 lastIndex = accounts.length - 1;

        if (index != lastIndex) {
            address lastAccount = accounts[lastIndex];
            accounts[index] = lastAccount;
            _accountIndexInGroup[groupId][lastAccount] = index;
        }

        accounts.pop();
        delete _accountIndexInGroup[groupId][account];
    }
}
