// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupTokenJoin} from "../interface/base/IGroupTokenJoin.sol";
import {GroupManager} from "./GroupManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ArrayUtils} from "@core/lib/ArrayUtils.sol";

/// @title GroupTokenJoin
/// @notice Handles account joining/exiting groups with token participation
abstract contract GroupTokenJoin is
    GroupManager,
    ReentrancyGuard,
    IGroupTokenJoin
{
    // ============================================
    // STATE VARIABLES - IMMUTABLE CONFIG
    // ============================================

    /// @notice The token used for joining groups
    address public immutable joinTokenAddress;

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Mapping from account address to join info
    mapping(address => JoinInfo) internal _joinInfo;

    /// @notice Mapping from group ID to list of accounts
    mapping(uint256 => address[]) internal _groupAccounts;

    /// @notice Mapping from group ID to account to index in _groupAccounts
    mapping(uint256 => mapping(address => uint256))
        internal _accountIndexInGroup;

    /// @notice Mapping: account => round => groupId (history)
    mapping(address => mapping(uint256 => uint256))
        internal _accountGroupByRound;

    /// @notice Mapping: account => rounds[] (rounds when account changed groups)
    mapping(address => uint256[]) internal _accountGroupChangeRounds;

    /// @notice Mapping: groupId => round => totalJoinedAmount (history)
    mapping(uint256 => mapping(uint256 => uint256)) internal _groupTotalByRound;

    /// @notice Mapping: groupId => rounds[] (rounds when group total changed)
    mapping(uint256 => uint256[]) internal _groupTotalChangeRounds;

    /// @dev ERC20 interface for the join token
    IERC20 internal _joinToken;

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /// @notice Initialize the group token join
    /// @param joinTokenAddress_ The token that can be used to join groups
    constructor(address joinTokenAddress_) {
        if (joinTokenAddress_ == address(0)) {
            revert IGroupTokenJoin.NotInGroup();
        }
        joinTokenAddress = joinTokenAddress_;
        _joinToken = IERC20(joinTokenAddress_);
    }

    // ============================================
    // JOIN/EXIT OPERATIONS
    // ============================================

    /// @notice Join a group with tokens (can be called multiple times)
    function join(uint256 groupId, uint256 amount) public virtual nonReentrant {
        _beforeJoin(groupId, msg.sender);

        JoinInfo storage participation = _joinInfo[msg.sender];
        bool isFirstJoin = participation.groupId == 0;

        // If already in a group, must be the same group
        if (!isFirstJoin && participation.groupId != groupId) {
            revert IGroupTokenJoin.AlreadyInOtherGroup();
        }

        GroupInfo storage group = _groups[groupId];

        if (group.startedRound == 0 || group.isStopped) {
            revert IGroupTokenJoin.CannotJoinStoppedGroup();
        }

        // Check minimum only for first join
        if (isFirstJoin) {
            uint256 effectiveMin = group.groupMinJoinAmount > minJoinAmount
                ? group.groupMinJoinAmount
                : minJoinAmount;
            if (amount == 0 || amount < effectiveMin) {
                revert IGroupTokenJoin.AmountBelowMinimum();
            }
        }

        // Check max amount (group level and account level)
        uint256 newTotal = participation.amount + amount;
        if (
            group.groupMaxJoinAmount > 0 && newTotal > group.groupMaxJoinAmount
        ) {
            revert IGroupTokenJoin.AmountExceedsAccountCap();
        }
        uint256 accountMaxAmount = calculateJoinMaxAmount();
        if (newTotal > accountMaxAmount) {
            revert IGroupTokenJoin.AmountExceedsAccountCap();
        }

        if (!checkCapacityAvailable(groupId, amount)) {
            revert IGroupTokenJoin.GroupCapacityFull();
        }

        _joinToken.transferFrom(msg.sender, address(this), amount);

        uint256 currentRound = _join.currentRound();
        participation.groupId = groupId;
        participation.amount = newTotal;

        group.totalJoinedAmount += amount;
        _recordGroupTotal(groupId, group.totalJoinedAmount, currentRound);

        // Record history and add to group list only on first join
        if (isFirstJoin) {
            participation.joinedRound = currentRound;

            uint256[] storage changeRounds = _accountGroupChangeRounds[
                msg.sender
            ];
            if (
                changeRounds.length == 0 ||
                changeRounds[changeRounds.length - 1] != currentRound
            ) {
                changeRounds.push(currentRound);
            }
            _accountGroupByRound[msg.sender][currentRound] = groupId;

            uint256 accountIndex = _groupAccounts[groupId].length;
            _groupAccounts[groupId].push(msg.sender);
            _accountIndexInGroup[groupId][msg.sender] = accountIndex;

            _addAccount(msg.sender);
        }

        emit Join(groupId, msg.sender, amount, currentRound);
    }

    /// @notice Exit from current group
    function exit() public virtual nonReentrant {
        JoinInfo storage participation = _joinInfo[msg.sender];
        if (participation.groupId == 0) revert IGroupTokenJoin.NotInGroup();

        uint256 groupId = participation.groupId;
        _beforeExit(groupId, msg.sender);

        uint256 amount = participation.amount;
        GroupInfo storage group = _groups[groupId];

        uint256 currentRound = _join.currentRound();
        uint256[] storage changeRounds = _accountGroupChangeRounds[msg.sender];
        if (
            changeRounds.length == 0 ||
            changeRounds[changeRounds.length - 1] != currentRound
        ) {
            changeRounds.push(currentRound);
        }
        _accountGroupByRound[msg.sender][currentRound] = 0;

        group.totalJoinedAmount -= amount;
        _recordGroupTotal(groupId, group.totalJoinedAmount, currentRound);

        _removeAccountFromGroup(groupId, msg.sender);
        delete _joinInfo[msg.sender];
        _removeAccount(msg.sender);

        _joinToken.transfer(msg.sender, amount);

        emit Exit(groupId, msg.sender, amount, currentRound);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /// @dev Get account's participation information
    function getJoinInfo(
        address account
    ) external view returns (IGroupTokenJoin.JoinInfo memory) {
        JoinInfo memory p = _joinInfo[account];
        return
            IGroupTokenJoin.JoinInfo({
                groupId: p.groupId,
                amount: p.amount,
                joinedRound: p.joinedRound
            });
    }

    /// @notice Get all accounts in a group
    function getGroupAccounts(
        uint256 groupId
    ) external view returns (address[] memory) {
        return _groupAccounts[groupId];
    }

    /// @notice Check if account can join group
    function canAccountJoinGroup(
        address account,
        uint256 groupId,
        uint256 amount
    ) external view returns (bool canJoin, string memory reason) {
        GroupInfo storage group = _groups[groupId];
        JoinInfo storage participation = _joinInfo[account];
        bool isFirstJoin = participation.groupId == 0;

        if (group.startedRound == 0) {
            return (false, "Group does not exist");
        }
        if (group.isStopped) {
            return (false, "Group is stopped");
        }
        if (!isFirstJoin && participation.groupId != groupId) {
            return (false, "Already in other group");
        }

        // Check minimum only for first join
        if (isFirstJoin) {
            uint256 effectiveMin = group.groupMinJoinAmount > minJoinAmount
                ? group.groupMinJoinAmount
                : minJoinAmount;
            if (amount < effectiveMin) {
                return (false, "Amount below minimum");
            }
        }

        uint256 newTotal = participation.amount + amount;
        if (
            group.groupMaxJoinAmount > 0 && newTotal > group.groupMaxJoinAmount
        ) {
            return (false, "Amount exceeds group max");
        }

        uint256 accountMaxAmount = calculateJoinMaxAmount();
        if (newTotal > accountMaxAmount) {
            return (false, "Amount exceeds account cap");
        }
        if (!checkCapacityAvailable(groupId, amount)) {
            return (false, "Group capacity full");
        }

        return (true, "");
    }

    /// @notice Get which group an account was in at end of a specific round
    function getAccountGroupByRound(
        address account,
        uint256 round
    ) public view returns (uint256 groupId) {
        (bool found, uint256 nearestRound) = ArrayUtils
            .findLeftNearestOrEqualValue(
                _accountGroupChangeRounds[account],
                round
            );
        if (!found) return 0;
        return _accountGroupByRound[account][nearestRound];
    }

    /// @notice Get group's total joined amount at end of a specific round
    function getGroupTotalByRound(
        uint256 groupId,
        uint256 round
    ) public view returns (uint256) {
        (bool found, uint256 nearestRound) = ArrayUtils
            .findLeftNearestOrEqualValue(
                _groupTotalChangeRounds[groupId],
                round
            );
        if (!found) return 0;
        return _groupTotalByRound[groupId][nearestRound];
    }

    // ============================================
    // INTERNAL HELPERS
    // ============================================

    /// @dev Record group total history
    function _recordGroupTotal(
        uint256 groupId,
        uint256 total,
        uint256 currentRound
    ) internal {
        uint256[] storage changeRounds = _groupTotalChangeRounds[groupId];
        if (
            changeRounds.length == 0 ||
            changeRounds[changeRounds.length - 1] != currentRound
        ) {
            changeRounds.push(currentRound);
        }
        _groupTotalByRound[groupId][currentRound] = total;
    }

    /// @dev Remove account from group's account list
    function _removeAccountFromGroup(
        uint256 groupId,
        address account
    ) internal {
        uint256 accountIndex = _accountIndexInGroup[groupId][account];
        address[] storage accounts = _groupAccounts[groupId];
        uint256 lastIndex = accounts.length - 1;

        if (accountIndex != lastIndex) {
            address lastAccount = accounts[lastIndex];
            accounts[accountIndex] = lastAccount;
            _accountIndexInGroup[groupId][lastAccount] = accountIndex;
        }

        accounts.pop();
        delete _accountIndexInGroup[groupId][account];
    }

    // ============================================
    // HOOKS
    // ============================================

    /// @dev Hook called BEFORE account joins
    function _beforeJoin(uint256 groupId, address account) internal virtual {}

    /// @dev Hook called BEFORE account exits
    function _beforeExit(uint256 groupId, address account) internal virtual {}

    // ============================================
    // ABSTRACT METHODS
    // ============================================

    /// @dev Add account to tracking
    function _addAccount(address account) internal virtual;

    /// @dev Remove account from tracking
    function _removeAccount(address account) internal virtual;
}
