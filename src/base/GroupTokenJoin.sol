// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupTokenJoin} from "../interface/base/IGroupTokenJoin.sol";
import {GroupCore} from "./GroupCore.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {RoundHistoryUint256} from "@extension/src/lib/RoundHistoryUint256.sol";

using RoundHistoryUint256 for RoundHistoryUint256.History;

/// @title GroupTokenJoin
/// @notice Handles token-based group joining and exiting
abstract contract GroupTokenJoin is
    GroupCore,
    ReentrancyGuard,
    IGroupTokenJoin
{
    // ============ Immutables ============

    address public immutable JOIN_TOKEN_ADDRESS;

    // ============ State ============

    IERC20 internal _joinToken;

    // Account state
    mapping(address => JoinInfo) internal _joinInfo;
    mapping(address => RoundHistoryUint256.History)
        internal _groupIdHistoryByAccount;

    // Group state
    mapping(uint256 => address[]) internal _accountsByGroupId;
    mapping(uint256 => mapping(address => uint256))
        internal _accountIndexInGroup;
    mapping(uint256 => RoundHistoryUint256.History)
        internal _totalJoinedAmountHistoryByGroupId;
    RoundHistoryUint256.History internal _totalJoinedAmountHistory;
    uint256 internal _totalJoinedAmount;

    // ============ Constructor ============

    constructor(address joinTokenAddress_) {
        if (joinTokenAddress_ == address(0)) revert InvalidAddress();
        JOIN_TOKEN_ADDRESS = joinTokenAddress_;
        _joinToken = IERC20(joinTokenAddress_);
    }

    // ============ Write Functions ============

    function join(uint256 groupId, uint256 amount) public virtual nonReentrant {
        if (amount == 0) revert InvalidAmount();

        _beforeJoin(groupId, msg.sender);

        JoinInfo storage info = _joinInfo[msg.sender];
        GroupInfo storage group = _groupInfo[groupId];
        bool isFirstJoin = info.groupId == 0;

        // Validate group and membership
        if (!isFirstJoin && info.groupId != groupId)
            revert AlreadyInOtherGroup();
        if (!group.isActive) revert CannotJoinDeactivatedGroup();

        // Validate amount
        if (isFirstJoin) {
            uint256 minAmount = _max(group.groupMinJoinAmount, MIN_JOIN_AMOUNT);
            if (amount < minAmount) revert AmountBelowMinimum();
        }

        uint256 newTotal = info.amount + amount;
        if (
            group.groupMaxJoinAmount > 0 && newTotal > group.groupMaxJoinAmount
        ) {
            revert AmountExceedsAccountCap();
        }
        if (newTotal > calculateJoinMaxAmount())
            revert AmountExceedsAccountCap();
        if (group.totalJoinedAmount + amount > group.capacity)
            revert GroupCapacityFull();

        // Transfer tokens and update state
        _joinToken.transferFrom(msg.sender, address(this), amount);

        uint256 currentRound = _join.currentRound();
        info.groupId = groupId;
        info.amount = newTotal;
        group.totalJoinedAmount += amount;

        _totalJoinedAmountHistoryByGroupId[groupId].record(
            currentRound,
            group.totalJoinedAmount
        );
        _totalJoinedAmount += amount;
        _totalJoinedAmountHistory.record(currentRound, _totalJoinedAmount);

        if (isFirstJoin) {
            info.joinedRound = currentRound;
            _groupIdHistoryByAccount[msg.sender].record(currentRound, groupId);
            _addAccountToGroup(groupId, msg.sender);
            _addAccount(msg.sender);
        }

        emit Join(groupId, msg.sender, amount, currentRound);
    }

    function exit() public virtual nonReentrant {
        JoinInfo storage info = _joinInfo[msg.sender];
        if (info.groupId == 0) revert NotInGroup();

        uint256 groupId = info.groupId;
        uint256 amount = info.amount;

        _beforeExit(groupId, msg.sender);

        uint256 currentRound = _join.currentRound();
        GroupInfo storage group = _groupInfo[groupId];

        // Update state
        _groupIdHistoryByAccount[msg.sender].record(currentRound, 0);
        group.totalJoinedAmount -= amount;
        _totalJoinedAmountHistoryByGroupId[groupId].record(
            currentRound,
            group.totalJoinedAmount
        );
        _totalJoinedAmount -= amount;
        _totalJoinedAmountHistory.record(currentRound, _totalJoinedAmount);

        _removeAccountFromGroup(groupId, msg.sender);
        delete _joinInfo[msg.sender];
        _removeAccount(msg.sender);

        // Transfer tokens back
        _joinToken.transfer(msg.sender, amount);

        emit Exit(groupId, msg.sender, amount, currentRound);
    }

    // ============ View Functions ============

    function joinInfo(address account) external view returns (JoinInfo memory) {
        return _joinInfo[account];
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
        return _totalJoinedAmount;
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

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    // ============ Hooks ============

    function _beforeJoin(uint256 groupId, address account) internal virtual {}

    function _beforeExit(uint256 groupId, address account) internal virtual {}

    // ============ Abstract Functions ============

    function _addAccount(address account) internal virtual;

    function _removeAccount(address account) internal virtual;
}
