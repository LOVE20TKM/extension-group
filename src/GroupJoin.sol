// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupJoin} from "./interface/IGroupJoin.sol";
import {
    ILOVE20ExtensionGroupActionFactory
} from "./interface/ILOVE20ExtensionGroupActionFactory.sol";
import {
    ILOVE20ExtensionGroupAction
} from "./interface/ILOVE20ExtensionGroupAction.sol";
import {
    IExtensionCenter
} from "@extension/src/interface/IExtensionCenter.sol";
import {ILOVE20Submit, ActionInfo} from "@core/interfaces/ILOVE20Submit.sol";
import {IGroupManager} from "./interface/IGroupManager.sol";
import {ILOVE20Group} from "@group/interfaces/ILOVE20Group.sol";
import {ILOVE20Join} from "@core/interfaces/ILOVE20Join.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {RoundHistoryUint256} from "@extension/src/lib/RoundHistoryUint256.sol";
import {RoundHistoryAddress} from "@extension/src/lib/RoundHistoryAddress.sol";

using RoundHistoryUint256 for RoundHistoryUint256.History;
using RoundHistoryAddress for RoundHistoryAddress.History;
using SafeERC20 for IERC20;

/// @title GroupJoin
/// @notice Singleton contract handling token-based group joining and exiting
/// @dev Users call directly, uses extension address from tokenAddress and actionId
contract GroupJoin is IGroupJoin, ReentrancyGuard {
    // ============ Immutables ============

    ILOVE20ExtensionGroupActionFactory internal _factory;
    IExtensionCenter internal _center;
    IGroupManager internal _groupManager;
    ILOVE20Group internal _group;
    ILOVE20Join internal _join;

    // ============ State ============

    address internal _factoryAddress;
    bool internal _initialized;

    // extension => account => joinedRound
    mapping(address => mapping(address => uint256))
        internal _joinedRoundByAccount;
    // extension => account => groupId history
    mapping(address => mapping(address => RoundHistoryUint256.History))
        internal _groupIdHistoryByAccount;
    // extension => account => amount history
    mapping(address => mapping(address => RoundHistoryUint256.History))
        internal _amountHistoryByAccount;

    // extension => groupId => accountCount history
    mapping(address => mapping(uint256 => RoundHistoryUint256.History))
        internal _accountCountByGroupIdHistory;
    // extension => groupId => index => account history
    mapping(address => mapping(uint256 => mapping(uint256 => RoundHistoryAddress.History)))
        internal _accountByGroupIdAndIndexHistory;
    // extension => groupId => account => index history
    mapping(address => mapping(uint256 => mapping(address => RoundHistoryUint256.History)))
        internal _accountIndexInGroupHistory;

    // extension => groupId => totalJoinedAmount history
    mapping(address => mapping(uint256 => RoundHistoryUint256.History))
        internal _totalJoinedAmountHistoryByGroupId;
    // extension => totalJoinedAmount history
    mapping(address => RoundHistoryUint256.History)
        internal _totalJoinedAmountHistory;

    // ============ Constructor ============

    constructor() {
        // Factory will be set via initialize()
    }

    // ============ Initialization ============

    /// @inheritdoc IGroupJoin
    function initialize(address factory_) external {
        if (_initialized) revert AlreadyInitialized();
        if (factory_ == address(0)) revert InvalidFactory();

        _factoryAddress = factory_;
        _factory = ILOVE20ExtensionGroupActionFactory(factory_);
        _center = IExtensionCenter(_factory.center());
        _groupManager = IGroupManager(_factory.GROUP_MANAGER_ADDRESS());
        _group = ILOVE20Group(_factory.GROUP_ADDRESS());
        _join = ILOVE20Join(_center.joinAddress());

        _initialized = true;
    }

    // ============ Config Functions ============

    /// @inheritdoc IGroupJoin
    function FACTORY_ADDRESS() external view override returns (address) {
        return _factoryAddress;
    }

    // ============ Modifiers ============

    modifier onlyValidExtension(address tokenAddress, uint256 actionId) {
        ILOVE20Submit submit = ILOVE20Submit(_center.submitAddress());
        ActionInfo memory actionInfo = submit.actionInfo(
            tokenAddress,
            actionId
        );
        address extension = actionInfo.body.whiteListAddress;

        if (!_factory.exists(extension)) {
            revert InvalidFactory();
        }
        _;
    }

    // ============ Internal Helpers ============

    /// @dev Get extension address from tokenAddress and actionId
    function _getExtension(
        address tokenAddress,
        uint256 actionId
    ) internal view returns (address extension) {
        ILOVE20Submit submit = ILOVE20Submit(_center.submitAddress());
        ActionInfo memory actionInfo = submit.actionInfo(
            tokenAddress,
            actionId
        );
        extension = actionInfo.body.whiteListAddress;
        if (extension == address(0)) revert InvalidFactory();
    }

    // ============ Write Functions ============

    /// @inheritdoc IGroupJoin
    function join(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 amount,
        string[] memory verificationInfos
    )
        external
        override
        nonReentrant
        onlyValidExtension(tokenAddress, actionId)
    {
        if (amount == 0) revert JoinAmountZero();

        address extension = _getExtension(tokenAddress, actionId);
        uint256 currentRound = _join.currentRound();

        _processJoin(
            extension,
            tokenAddress,
            actionId,
            groupId,
            amount,
            currentRound,
            msg.sender,
            verificationInfos
        );

        emit Join(
            tokenAddress,
            currentRound,
            actionId,
            groupId,
            msg.sender,
            amount
        );
    }

    /// @inheritdoc IGroupJoin
    function exit(
        address tokenAddress,
        uint256 actionId
    )
        external
        override
        nonReentrant
        onlyValidExtension(tokenAddress, actionId)
    {
        address extension = _getExtension(tokenAddress, actionId);
        uint256 groupId = _groupIdHistoryByAccount[extension][msg.sender]
            .latestValue();
        if (groupId == 0) revert NotInGroup();

        uint256 amount = _amountHistoryByAccount[extension][msg.sender]
            .latestValue();
        uint256 currentRound = _join.currentRound();

        // Update state
        _groupIdHistoryByAccount[extension][msg.sender].record(currentRound, 0);
        _amountHistoryByAccount[extension][msg.sender].record(currentRound, 0);

        // Update totalJoinedAmount history
        _totalJoinedAmountHistoryByGroupId[extension][groupId].record(
            currentRound,
            _totalJoinedAmountHistoryByGroupId[extension][groupId]
                .latestValue() - amount
        );
        _totalJoinedAmountHistory[extension].record(
            currentRound,
            _totalJoinedAmountHistory[extension].latestValue() - amount
        );

        _removeAccountFromGroup(extension, currentRound, groupId, msg.sender);
        delete _joinedRoundByAccount[extension][msg.sender];
        _center.removeAccount(tokenAddress, actionId, msg.sender);

        // Get join token address from GroupManager config
        address joinTokenAddress = _getJoinTokenAddress(
            extension,
            tokenAddress,
            actionId
        );
        IERC20 joinToken = IERC20(joinTokenAddress);

        // Transfer tokens back
        joinToken.safeTransfer(msg.sender, amount);

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

    /// @inheritdoc IGroupJoin
    function joinInfo(
        address tokenAddress,
        uint256 actionId,
        address account
    )
        external
        view
        override
        returns (uint256 joinedRound, uint256 amount, uint256 groupId)
    {
        address extension = _getExtension(tokenAddress, actionId);
        return (
            _joinedRoundByAccount[extension][account],
            _amountHistoryByAccount[extension][account].latestValue(),
            _groupIdHistoryByAccount[extension][account].latestValue()
        );
    }

    /// @inheritdoc IGroupJoin
    function accountsByGroupIdCount(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return _accountCountByGroupIdHistory[extension][groupId].latestValue();
    }

    /// @inheritdoc IGroupJoin
    function accountsByGroupIdAtIndex(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 index
    ) external view override returns (address) {
        address extension = _getExtension(tokenAddress, actionId);
        return
            _accountByGroupIdAndIndexHistory[extension][groupId][index]
                .latestValue();
    }

    /// @inheritdoc IGroupJoin
    function groupIdByAccountByRound(
        address tokenAddress,
        uint256 actionId,
        address account,
        uint256 round
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return _groupIdHistoryByAccount[extension][account].value(round);
    }

    /// @inheritdoc IGroupJoin
    function totalJoinedAmountByGroupId(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return
            _totalJoinedAmountHistoryByGroupId[extension][groupId]
                .latestValue();
    }

    /// @inheritdoc IGroupJoin
    function totalJoinedAmountByGroupIdByRound(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 round
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return
            _totalJoinedAmountHistoryByGroupId[extension][groupId].value(round);
    }

    /// @inheritdoc IGroupJoin
    function totalJoinedAmount(
        address tokenAddress,
        uint256 actionId
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return _totalJoinedAmountHistory[extension].latestValue();
    }

    /// @inheritdoc IGroupJoin
    function totalJoinedAmountByRound(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return _totalJoinedAmountHistory[extension].value(round);
    }

    /// @inheritdoc IGroupJoin
    function accountCountByGroupIdByRound(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 round
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return _accountCountByGroupIdHistory[extension][groupId].value(round);
    }

    /// @inheritdoc IGroupJoin
    function accountByGroupIdAndIndexByRound(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 index,
        uint256 round
    ) external view override returns (address) {
        address extension = _getExtension(tokenAddress, actionId);
        return
            _accountByGroupIdAndIndexHistory[extension][groupId][index].value(
                round
            );
    }

    /// @inheritdoc IGroupJoin
    function amountByAccountByRound(
        address tokenAddress,
        uint256 actionId,
        address account,
        uint256 round
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return _amountHistoryByAccount[extension][account].value(round);
    }

    // ============ Internal Functions ============

    function _getJoinTokenAddress(
        address extension,
        address,
        uint256
    ) internal view returns (address) {
        return ILOVE20ExtensionGroupAction(extension).JOIN_TOKEN_ADDRESS();
    }

    function _processJoin(
        address extension,
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 amount,
        uint256 currentRound,
        address account,
        string[] memory verificationInfos
    ) internal {
        uint256 joinedGroupId = _groupIdHistoryByAccount[extension][account]
            .latestValue();
        bool isFirstJoin = joinedGroupId == 0;
        uint256 newTotal = _amountHistoryByAccount[extension][account]
            .latestValue() + amount;

        _validateJoinAmounts(
            extension,
            tokenAddress,
            actionId,
            groupId,
            amount,
            isFirstJoin,
            joinedGroupId,
            newTotal
        );

        _transferJoinToken(extension, account, amount);
        _updateJoinHistory(
            extension,
            groupId,
            amount,
            currentRound,
            account,
            newTotal
        );
        if (isFirstJoin) {
            _joinedRoundByAccount[extension][account] = currentRound;
            _groupIdHistoryByAccount[extension][account].record(
                currentRound,
                groupId
            );
            _addAccountToGroup(extension, currentRound, groupId, account);
            _center.addAccount(
                tokenAddress,
                actionId,
                account,
                verificationInfos
            );
        } else if (verificationInfos.length > 0) {
            _center.updateVerificationInfo(
                tokenAddress,
                actionId,
                account,
                verificationInfos
            );
        }
    }

    function _transferJoinToken(
        address extension,
        address account,
        uint256 amount
    ) internal {
        address joinTokenAddress = ILOVE20ExtensionGroupAction(extension)
            .JOIN_TOKEN_ADDRESS();
        IERC20(joinTokenAddress).safeTransferFrom(
            account,
            address(this),
            amount
        );
    }

    function _updateJoinHistory(
        address extension,
        uint256 groupId,
        uint256 amount,
        uint256 currentRound,
        address account,
        uint256 newTotal
    ) internal {
        RoundHistoryUint256.History
            storage groupHistory = _totalJoinedAmountHistoryByGroupId[
                extension
            ][groupId];
        groupHistory.record(currentRound, groupHistory.latestValue() + amount);

        RoundHistoryUint256.History
            storage totalHistory = _totalJoinedAmountHistory[extension];
        totalHistory.record(currentRound, totalHistory.latestValue() + amount);

        _amountHistoryByAccount[extension][account].record(
            currentRound,
            newTotal
        );
    }

    function _handleVerificationInfos(
        address tokenAddress,
        uint256 actionId,
        address account,
        bool isFirstJoin,
        uint256 groupId,
        uint256 currentRound,
        address extension,
        string[] memory verificationInfos
    ) internal {
        if (isFirstJoin) {
            _joinedRoundByAccount[extension][account] = currentRound;
            _groupIdHistoryByAccount[extension][account].record(
                currentRound,
                groupId
            );
            _addAccountToGroup(extension, currentRound, groupId, account);
            _center.addAccount(
                tokenAddress,
                actionId,
                account,
                verificationInfos
            );
        } else if (verificationInfos.length > 0) {
            _center.updateVerificationInfo(
                tokenAddress,
                actionId,
                account,
                verificationInfos
            );
        }
    }

    function _validateJoinAmounts(
        address extension,
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 amount,
        bool isFirstJoin,
        uint256 joinedGroupId,
        uint256 newTotal
    ) internal view {
        _validateGroupInfo(
            extension,
            tokenAddress,
            actionId,
            groupId,
            amount,
            isFirstJoin,
            joinedGroupId,
            newTotal
        );
        _validateOwnerCapacity(
            extension,
            tokenAddress,
            actionId,
            groupId,
            amount
        );
    }

    function _validateGroupInfo(
        address extension,
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 amount,
        bool isFirstJoin,
        uint256 joinedGroupId,
        uint256 newTotal
    ) internal view {
        if (!isFirstJoin && joinedGroupId != groupId)
            revert AlreadyInOtherGroup();

        (
            ,
            ,
            uint256 maxCapacity,
            uint256 minJoinAmount,
            uint256 maxJoinAmount,
            uint256 maxAccounts,
            bool isActive,
            ,

        ) = _groupManager.groupInfo(tokenAddress, actionId, groupId);

        if (!isActive) revert CannotJoinDeactivatedGroup();

        if (isFirstJoin) {
            _validateFirstJoin(
                extension,
                groupId,
                amount,
                maxAccounts,
                minJoinAmount
            );
        }

        if (maxJoinAmount > 0 && newTotal > maxJoinAmount) {
            revert AmountExceedsAccountCap();
        }
        if (
            newTotal >
            _groupManager.calculateJoinMaxAmount(tokenAddress, actionId)
        ) revert AmountExceedsAccountCap();

        // Check group's max capacity (if set)
        if (maxCapacity > 0) {
            _validateGroupCapacity(extension, groupId, amount, maxCapacity);
        }
    }

    function _validateFirstJoin(
        address extension,
        uint256 groupId,
        uint256 amount,
        uint256 maxAccounts,
        uint256 minJoinAmount
    ) internal view {
        if (maxAccounts > 0) {
            if (
                _accountCountByGroupIdHistory[extension][groupId]
                    .latestValue() >= maxAccounts
            ) revert GroupAccountsFull();
        }
        if (amount < minJoinAmount) revert AmountBelowMinimum();
    }

    function _validateGroupCapacity(
        address extension,
        uint256 groupId,
        uint256 amount,
        uint256 maxCapacity
    ) internal view {
        mapping(uint256 => RoundHistoryUint256.History)
            storage groupHistory = _totalJoinedAmountHistoryByGroupId[
                extension
            ];
        RoundHistoryUint256.History storage history = groupHistory[groupId];
        if (history.latestValue() + amount > maxCapacity) {
            revert GroupCapacityExceeded();
        }
    }

    function _validateOwnerCapacity(
        address extension,
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 amount
    ) internal view {
        address groupOwner = _group.ownerOf(groupId);
        uint256 ownerTotalJoined = _totalJoinedAmountByOwner(
            extension,
            tokenAddress,
            actionId,
            groupOwner
        );
        uint256 ownerMaxVerifyCapacity = _groupManager.maxVerifyCapacityByOwner(
            tokenAddress,
            actionId,
            groupOwner
        );
        if (ownerTotalJoined + amount > ownerMaxVerifyCapacity) {
            revert OwnerCapacityExceeded();
        }
    }

    /// @dev Calculate total joined amount for all active groups owned by owner
    function _totalJoinedAmountByOwner(
        address extension,
        address tokenAddress,
        uint256 actionId,
        address owner
    ) internal view returns (uint256 total) {
        uint256[] memory ownerGroupIds = _groupManager.activeGroupIdsByOwner(
            tokenAddress,
            actionId,
            owner
        );
        for (uint256 i = 0; i < ownerGroupIds.length; i++) {
            total += _totalJoinedAmountHistoryByGroupId[extension][
                ownerGroupIds[i]
            ].latestValue();
        }
    }

    function _addAccountToGroup(
        address extension,
        uint256 round,
        uint256 groupId,
        address account
    ) internal {
        uint256 accountCount = _accountCountByGroupIdHistory[extension][groupId]
            .latestValue();

        _accountByGroupIdAndIndexHistory[extension][groupId][accountCount]
            .record(round, account);
        _accountIndexInGroupHistory[extension][groupId][account].record(
            round,
            accountCount
        );
        _accountCountByGroupIdHistory[extension][groupId].record(
            round,
            accountCount + 1
        );
    }

    function _removeAccountFromGroup(
        address extension,
        uint256 round,
        uint256 groupId,
        address account
    ) internal {
        uint256 index = _accountIndexInGroupHistory[extension][groupId][account]
            .latestValue();
        uint256 lastIndex = _accountCountByGroupIdHistory[extension][groupId]
            .latestValue() - 1;

        // Swap and pop
        if (index != lastIndex) {
            address lastAccount = _accountByGroupIdAndIndexHistory[extension][
                groupId
            ][lastIndex].latestValue();
            _accountByGroupIdAndIndexHistory[extension][groupId][index].record(
                round,
                lastAccount
            );
            _accountIndexInGroupHistory[extension][groupId][lastAccount].record(
                round,
                index
            );
        }
        _accountCountByGroupIdHistory[extension][groupId].record(
            round,
            lastIndex
        );
    }
}
