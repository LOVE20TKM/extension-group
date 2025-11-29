// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupTokenJoin} from "../interface/base/IGroupTokenJoin.sol";
import {GroupManager} from "./GroupManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {RoundHistory} from "@extension/src/lib/RoundHistory.sol";

using RoundHistory for RoundHistory.History;

/// @title GroupTokenJoin
/// @notice Handles token-based group joining and exiting
abstract contract GroupTokenJoin is
    GroupManager,
    ReentrancyGuard,
    IGroupTokenJoin
{
    // ============ Immutables ============

    address public immutable joinTokenAddress;

    // ============ State ============

    IERC20 internal _joinToken;

    // Account state
    mapping(address => JoinInfo) internal _joinInfo;
    mapping(address => RoundHistory.History) internal _accountGroupHistory;

    // Group state
    mapping(uint256 => address[]) internal _groupAccounts;
    mapping(uint256 => mapping(address => uint256))
        internal _accountIndexInGroup;
    mapping(uint256 => RoundHistory.History) internal _groupTotalHistory;

    // ============ Constructor ============

    constructor(address joinTokenAddress_) {
        if (joinTokenAddress_ == address(0)) revert InvalidAddress();
        joinTokenAddress = joinTokenAddress_;
        _joinToken = IERC20(joinTokenAddress_);
    }

    // ============ Write Functions ============

    function join(uint256 groupId, uint256 amount) public virtual nonReentrant {
        if (amount == 0) revert InvalidAmount();

        _beforeJoin(groupId, msg.sender);

        JoinInfo storage info = _joinInfo[msg.sender];
        GroupInfo storage group = _groups[groupId];
        bool isFirstJoin = info.groupId == 0;

        // Validate group and membership
        if (!isFirstJoin && info.groupId != groupId)
            revert AlreadyInOtherGroup();
        if (group.activatedRound == 0 || group.isDeactivated)
            revert CannotJoinDeactivatedGroup();

        // Validate amount
        if (isFirstJoin) {
            uint256 minAmount = _max(group.groupMinJoinAmount, minJoinAmount);
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

        _recordGroupTotal(groupId, group.totalJoinedAmount, currentRound);

        if (isFirstJoin) {
            info.joinedRound = currentRound;
            _recordAccountGroup(msg.sender, groupId, currentRound);
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
        GroupInfo storage group = _groups[groupId];

        // Update state
        _recordAccountGroup(msg.sender, 0, currentRound);
        group.totalJoinedAmount -= amount;
        _recordGroupTotal(groupId, group.totalJoinedAmount, currentRound);

        _removeAccountFromGroup(groupId, msg.sender);
        delete _joinInfo[msg.sender];
        _removeAccount(msg.sender);

        // Transfer tokens back
        _joinToken.transfer(msg.sender, amount);

        emit Exit(groupId, msg.sender, amount, currentRound);
    }

    // ============ View Functions ============

    function getJoinInfo(
        address account
    ) external view returns (JoinInfo memory) {
        return _joinInfo[account];
    }

    function getGroupAccounts(
        uint256 groupId
    ) external view returns (address[] memory) {
        return _groupAccounts[groupId];
    }

    function getAccountGroupByRound(
        address account,
        uint256 round
    ) public view returns (uint256) {
        return _accountGroupHistory[account].value(round);
    }

    function getGroupTotalByRound(
        uint256 groupId,
        uint256 round
    ) public view returns (uint256) {
        return _groupTotalHistory[groupId].value(round);
    }

    // ============ Internal Functions ============

    function _recordAccountGroup(
        address account,
        uint256 groupId,
        uint256 round
    ) internal {
        _accountGroupHistory[account].record(round, groupId);
    }

    function _recordGroupTotal(
        uint256 groupId,
        uint256 total,
        uint256 round
    ) internal {
        _groupTotalHistory[groupId].record(round, total);
    }

    function _addAccountToGroup(uint256 groupId, address account) internal {
        _accountIndexInGroup[groupId][account] = _groupAccounts[groupId].length;
        _groupAccounts[groupId].push(account);
    }

    function _removeAccountFromGroup(
        uint256 groupId,
        address account
    ) internal {
        address[] storage accounts = _groupAccounts[groupId];
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
