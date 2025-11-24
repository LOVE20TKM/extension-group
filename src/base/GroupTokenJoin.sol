// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupTokenJoin} from "../interface/base/IGroupTokenJoin.sol";
import {IGroupManager} from "../interface/base/IGroupManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title GroupTokenJoin
/// @notice Handles account joining/exiting groups with token participation
/// @dev Does not inherit GroupManager to avoid diamond inheritance
abstract contract GroupTokenJoin is ReentrancyGuard {
    // ============================================
    // STATE VARIABLES - IMMUTABLE CONFIG
    // ============================================

    /// @notice The token used for joining groups
    address public immutable joinTokenAddress;

    // ============================================
    // EVENTS
    // ============================================

    event JoinGroup(
        uint256 indexed groupId,
        address indexed account,
        uint256 amount,
        uint256 round
    );

    event ExitGroup(
        uint256 indexed groupId,
        address indexed account,
        uint256 amount,
        uint256 round
    );

    // ============================================
    // STRUCTS
    // ============================================

    /// @notice Join information
    struct JoinInfo {
        uint256 groupId;
        uint256 amount;
        uint256 joinedRound;
    }

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

    /// @dev ERC20 interface for the join token
    IERC20 internal _joinToken;

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /// @notice Initialize the group token join
    /// @param joinTokenAddress_ The token that can be used to join groups
    constructor(address joinTokenAddress_) {
        if (joinTokenAddress_ == address(0)) {
            revert IGroupTokenJoin.NotInGroup(); // reuse error for simplicity
        }
        joinTokenAddress = joinTokenAddress_;
        _joinToken = IERC20(joinTokenAddress_);
    }

    // ============================================
    // JOIN/EXIT OPERATIONS
    // ============================================

    /// @notice Join a group with tokens
    function joinGroup(
        uint256 groupId,
        uint256 amount
    ) public virtual nonReentrant {
        // Hook for snapshot mechanism (before state change)
        _beforeJoinGroup(groupId, msg.sender);

        // Check account is not already in a group
        JoinInfo storage participation = _joinInfo[msg.sender];
        if (participation.groupId != 0) revert IGroupTokenJoin.AlreadyInGroup();

        IGroupManager.GroupInfo memory group = _getGroupInfo(groupId);

        // Check group is active
        if (group.startedRound == 0 || group.isStopped) {
            revert IGroupTokenJoin.CannotJoinStoppedGroup();
        }

        // Validate amount
        if (amount == 0 || amount < group.minJoinAmount) {
            revert IGroupTokenJoin.AmountBelowMinimum();
        }
        if (group.maxJoinAmount > 0 && amount > group.maxJoinAmount) {
            revert IGroupTokenJoin.AmountExceedsAccountCap();
        }

        // Check account cap
        uint256 accountMaxAmount = _calculateJoinMaxAmount();
        if (amount > accountMaxAmount)
            revert IGroupTokenJoin.AmountExceedsAccountCap();

        // Check group capacity
        if (!_checkCapacityAvailable(groupId, amount)) {
            revert IGroupTokenJoin.GroupCapacityFull();
        }

        // Transfer tokens from account
        _joinToken.transferFrom(msg.sender, address(this), amount);

        // Update state
        uint256 currentRound = _getCurrentRound();
        participation.groupId = groupId;
        participation.amount = amount;
        participation.joinedRound = currentRound;

        _updateGrouptotalJoinedAmount(
            groupId,
            group.totalJoinedAmount + amount
        );

        // Record history
        uint256[] storage changeRounds = _accountGroupChangeRounds[msg.sender];
        if (
            changeRounds.length == 0 ||
            changeRounds[changeRounds.length - 1] != currentRound
        ) {
            changeRounds.push(currentRound);
        }
        _accountGroupByRound[msg.sender][currentRound] = groupId;

        // Add to group's account list
        uint256 accountIndex = _groupAccounts[groupId].length;
        _groupAccounts[groupId].push(msg.sender);
        _accountIndexInGroup[groupId][msg.sender] = accountIndex;

        // Add to accounts tracking
        _addAccount(msg.sender);

        emit JoinGroup(groupId, msg.sender, amount, currentRound);
    }

    /// @notice Exit from a group
    function exitGroup(uint256 groupId) public virtual nonReentrant {
        // Hook for snapshot mechanism (before state change)
        _beforeExit(groupId, msg.sender);

        JoinInfo storage participation = _joinInfo[msg.sender];

        // Check account is in a group
        if (participation.groupId == 0) revert IGroupTokenJoin.NotInGroup();

        // Check account is in specified group
        if (participation.groupId != groupId)
            revert IGroupTokenJoin.NotInThisGroup();

        uint256 amount = participation.amount;
        IGroupManager.GroupInfo memory group = _getGroupInfo(groupId);

        // Record history
        uint256 currentRound = _getCurrentRound();
        uint256[] storage changeRounds = _accountGroupChangeRounds[msg.sender];
        if (
            changeRounds.length == 0 ||
            changeRounds[changeRounds.length - 1] != currentRound
        ) {
            changeRounds.push(currentRound);
        }
        _accountGroupByRound[msg.sender][currentRound] = 0; // 0 means not in any group

        // Update group
        _updateGrouptotalJoinedAmount(
            groupId,
            group.totalJoinedAmount - amount
        );

        // Remove from group's account list
        _removeAccountFromGroup(groupId, msg.sender);

        // Clear participation
        delete _joinInfo[msg.sender];

        // Remove from accounts tracking
        _removeAccount(msg.sender);

        // Return tokens
        _joinToken.transfer(msg.sender, amount);

        emit ExitGroup(groupId, msg.sender, amount, currentRound);
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
        IGroupManager.GroupInfo memory group = _getGroupInfo(groupId);

        // Check if group exists
        if (group.startedRound == 0) {
            return (false, "Group does not exist");
        }

        // Check if group is stopped
        if (group.isStopped) {
            return (false, "Group is stopped");
        }

        // Check if account is already in a group
        if (_joinInfo[account].groupId != 0) {
            return (false, "Already in a group");
        }

        // Check minimum amount
        if (amount < group.minJoinAmount) {
            return (false, "Amount below minimum");
        }

        // Check maximum amount
        if (group.maxJoinAmount > 0 && amount > group.maxJoinAmount) {
            return (false, "Amount exceeds group max");
        }

        // Check account cap
        uint256 accountMaxAmount = _calculateJoinMaxAmount();
        if (amount > accountMaxAmount) {
            return (false, "Amount exceeds account cap");
        }

        // Check group capacity
        if (!_checkCapacityAvailable(groupId, amount)) {
            return (false, "Group capacity full");
        }

        return (true, "");
    }

    /// @notice Get which group an account was in during a specific round
    function getAccountGroupByRound(
        address account,
        uint256 round
    ) public view returns (uint256 groupId) {
        uint256[] storage changeRounds = _accountGroupChangeRounds[account];

        if (changeRounds.length == 0) {
            return 0;
        }

        // Binary search for nearest round <= target round
        uint256 left = 0;
        uint256 right = changeRounds.length;
        uint256 nearestIndex = type(uint256).max;

        while (left < right) {
            uint256 mid = (left + right) / 2;
            if (changeRounds[mid] <= round) {
                nearestIndex = mid;
                left = mid + 1;
            } else {
                right = mid;
            }
        }

        if (nearestIndex == type(uint256).max) {
            return 0;
        }

        uint256 nearestRound = changeRounds[nearestIndex];

        // If account joined/exited in THIS round, reward is based on PREVIOUS group
        if (nearestRound == round) {
            if (nearestIndex == 0) {
                return 0;
            }
            return
                _accountGroupByRound[account][changeRounds[nearestIndex - 1]];
        }

        // Normal case: account was already in this group
        return _accountGroupByRound[account][nearestRound];
    }

    // ============================================
    // INTERNAL HELPERS
    // ============================================

    /// @dev Remove account from group's account list
    function _removeAccountFromGroup(
        uint256 groupId,
        address account
    ) internal {
        uint256 accountIndex = _accountIndexInGroup[groupId][account];
        address[] storage accounts = _groupAccounts[groupId];
        uint256 lastIndex = accounts.length - 1;

        if (accountIndex != lastIndex) {
            // Move last account to removed position
            address lastAccount = accounts[lastIndex];
            accounts[accountIndex] = lastAccount;
            _accountIndexInGroup[groupId][lastAccount] = accountIndex;
        }

        // Remove last element
        accounts.pop();
        delete _accountIndexInGroup[groupId][account];
    }

    // ============================================
    // HOOKS (for subclasses to implement)
    // ============================================

    /// @dev Hook called BEFORE account joins (for snapshot mechanism)
    function _beforeJoinGroup(
        uint256 groupId,
        address account
    ) internal virtual {}

    /// @dev Hook called BEFORE account exits (for snapshot mechanism)
    function _beforeExit(uint256 groupId, address account) internal virtual {}

    /// @dev Check if capacity is available
    function _checkCapacityAvailable(
        uint256 groupId,
        uint256 amount
    ) internal view virtual returns (bool) {
        return _getGroupManager().checkCapacityAvailable(groupId, amount);
    }

    /// @dev Calculate max amount for account
    function _calculateJoinMaxAmount() internal view virtual returns (uint256) {
        return _getGroupManager().calculateJoinMaxAmount();
    }

    // ============================================
    // ABSTRACT METHODS
    // ============================================

    /// @dev Get GroupManager instance
    function _getGroupManager() internal view virtual returns (IGroupManager);

    /// @dev Add account to tracking
    function _addAccount(address account) internal virtual;

    /// @dev Remove account from tracking
    function _removeAccount(address account) internal virtual;

    /// @dev Get group info
    function _getGroupInfo(
        uint256 groupId
    ) internal view virtual returns (IGroupManager.GroupInfo memory);

    /// @dev Update group total participation
    function _updateGrouptotalJoinedAmount(
        uint256 groupId,
        uint256 newTotal
    ) internal virtual;

    /// @dev Get current round
    function _getCurrentRound() internal view virtual returns (uint256);
}
