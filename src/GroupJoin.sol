// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupJoin} from "./interface/IGroupJoin.sol";
import {
    IExtensionGroupActionFactory
} from "./interface/IExtensionGroupActionFactory.sol";
import {IGroupAction} from "./interface/IGroupAction.sol";
import {IExtension} from "@extension/src/interface/IExtension.sol";
import {IExtensionCenter} from "@extension/src/interface/IExtensionCenter.sol";
import {IGroupManager} from "./interface/IGroupManager.sol";
import {
    IERC721Enumerable
} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {ILOVE20Join} from "@core/interfaces/ILOVE20Join.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {RoundHistoryUint256} from "@extension/src/lib/RoundHistoryUint256.sol";
import {
    RoundHistoryAddressSet
} from "@extension/src/lib/RoundHistoryAddressSet.sol";

using RoundHistoryUint256 for RoundHistoryUint256.History;
using RoundHistoryAddressSet for RoundHistoryAddressSet.Storage;
using SafeERC20 for IERC20;

contract GroupJoin is IGroupJoin, ReentrancyGuard {
    address public FACTORY_ADDRESS;

    IExtensionGroupActionFactory internal _factory;
    IExtensionCenter internal _center;
    IGroupManager internal _groupManager;
    IERC721Enumerable internal _group;
    ILOVE20Join internal _join;

    bool internal _initialized;
    // extension => account => joinedRound
    mapping(address => mapping(address => uint256))
        internal _joinedRoundByAccount;
    // extension => account => groupId
    mapping(address => mapping(address => RoundHistoryUint256.History))
        internal _groupIdHistoryByAccount;
    // extension => account => amount
    mapping(address => mapping(address => RoundHistoryUint256.History))
        internal _amountHistoryByAccount;
    // extension => groupId => account list history
    mapping(address => mapping(uint256 => RoundHistoryAddressSet.Storage))
        internal _accountsHistory;
    // extension => groupId => totalJoinedAmount
    mapping(address => mapping(uint256 => RoundHistoryUint256.History))
        internal _totalJoinedAmountHistoryByGroupId;
    // extension => totalJoinedAmount
    mapping(address => RoundHistoryUint256.History)
        internal _totalJoinedAmountHistory;

    constructor() {}

    function initialize(address factory_) external {
        require(_initialized == false, "Already initialized");
        require(factory_ != address(0), "Invalid factory address");

        FACTORY_ADDRESS = factory_;
        _factory = IExtensionGroupActionFactory(factory_);
        _center = IExtensionCenter(_factory.CENTER_ADDRESS());
        _groupManager = IGroupManager(_factory.GROUP_MANAGER_ADDRESS());
        _group = IERC721Enumerable(_factory.GROUP_ADDRESS());
        _join = ILOVE20Join(_center.joinAddress());

        _initialized = true;
    }

    function join(
        address extension,
        uint256 groupId,
        uint256 amount,
        string[] memory verificationInfos
    ) external override nonReentrant onlyValidExtension(extension) {
        if (amount == 0) revert JoinAmountZero();

        address tokenAddress = IExtension(extension).TOKEN_ADDRESS();
        uint256 actionId = IExtension(extension).actionId();
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

    function exit(
        address extension
    ) external override nonReentrant onlyValidExtension(extension) {
        address tokenAddress = IExtension(extension).TOKEN_ADDRESS();
        uint256 actionId = IExtension(extension).actionId();
        uint256 groupId = _groupIdHistoryByAccount[extension][msg.sender]
            .latestValue();
        if (groupId == 0) revert NotInGroup();

        uint256 amount = _amountHistoryByAccount[extension][msg.sender]
            .latestValue();
        uint256 currentRound = _join.currentRound();

        _groupIdHistoryByAccount[extension][msg.sender].record(currentRound, 0);
        _amountHistoryByAccount[extension][msg.sender].record(currentRound, 0);

        _totalJoinedAmountHistoryByGroupId[extension][groupId].record(
            currentRound,
            _totalJoinedAmountHistoryByGroupId[extension][groupId]
                .latestValue() - amount
        );
        _totalJoinedAmountHistory[extension].record(
            currentRound,
            _totalJoinedAmountHistory[extension].latestValue() - amount
        );

        _accountsHistory[extension][groupId].remove(msg.sender, currentRound);
        delete _joinedRoundByAccount[extension][msg.sender];
        _center.removeAccount(tokenAddress, actionId, msg.sender);

        address joinTokenAddress = _getJoinTokenAddress(
            extension,
            tokenAddress,
            actionId
        );
        IERC20 joinToken = IERC20(joinTokenAddress);

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

    function joinInfo(
        address extension,
        address account
    )
        external
        view
        override
        returns (uint256 joinedRound, uint256 amount, uint256 groupId)
    {
        return (
            _joinedRoundByAccount[extension][account],
            _amountHistoryByAccount[extension][account].latestValue(),
            _groupIdHistoryByAccount[extension][account].latestValue()
        );
    }

    function accountsByGroupId(
        address extension,
        uint256 groupId
    ) external view override returns (address[] memory) {
        return _accountsHistory[extension][groupId].values();
    }

    function accountsByGroupIdCount(
        address extension,
        uint256 groupId
    ) external view override returns (uint256) {
        return _accountsHistory[extension][groupId].count();
    }

    function accountsByGroupIdAtIndex(
        address extension,
        uint256 groupId,
        uint256 index
    ) external view override returns (address) {
        return _accountsHistory[extension][groupId].atIndex(index);
    }

    function groupIdByAccountByRound(
        address extension,
        address account,
        uint256 round
    ) external view override returns (uint256) {
        return _groupIdHistoryByAccount[extension][account].value(round);
    }

    function totalJoinedAmountByGroupId(
        address extension,
        uint256 groupId
    ) external view override returns (uint256) {
        return
            _totalJoinedAmountHistoryByGroupId[extension][groupId]
                .latestValue();
    }

    function totalJoinedAmountByGroupIdByRound(
        address extension,
        uint256 groupId,
        uint256 round
    ) external view override returns (uint256) {
        return
            _totalJoinedAmountHistoryByGroupId[extension][groupId].value(round);
    }

    function totalJoinedAmount(
        address extension
    ) external view override returns (uint256) {
        return _totalJoinedAmountHistory[extension].latestValue();
    }

    function totalJoinedAmountByRound(
        address extension,
        uint256 round
    ) external view override returns (uint256) {
        return _totalJoinedAmountHistory[extension].value(round);
    }

    function accountsByGroupIdByRoundCount(
        address extension,
        uint256 groupId,
        uint256 round
    ) external view override returns (uint256) {
        return _accountsHistory[extension][groupId].countByRound(round);
    }
    function accountsByGroupIdByRound(
        address extension,
        uint256 groupId,
        uint256 round
    ) external view override returns (address[] memory) {
        return _accountsHistory[extension][groupId].valuesByRound(round);
    }

    function accountsByGroupIdByRoundAtIndex(
        address extension,
        uint256 groupId,
        uint256 round,
        uint256 index
    ) external view override returns (address) {
        return
            _accountsHistory[extension][groupId].atIndexByRound(index, round);
    }

    function amountByAccountByRound(
        address extension,
        address account,
        uint256 round
    ) external view override returns (uint256) {
        return _amountHistoryByAccount[extension][account].value(round);
    }

    modifier onlyValidExtension(address extension) {
        if (!_factory.exists(extension)) {
            revert NotRegisteredExtensionInFactory();
        }
        if (!IExtension(extension).initialized()) {
            revert ExtensionNotInitialized();
        }
        _;
    }

    function _getJoinTokenAddress(
        address extension,
        address,
        uint256
    ) internal view returns (address) {
        return IGroupAction(extension).JOIN_TOKEN_ADDRESS();
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
            _accountsHistory[extension][groupId].add(account, currentRound);
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
        address joinTokenAddress = IGroupAction(extension).JOIN_TOKEN_ADDRESS();
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

    function _validateJoinAmounts(
        address extension,
        uint256 groupId,
        uint256 amount,
        bool isFirstJoin,
        uint256 joinedGroupId,
        uint256 newTotal
    ) internal view {
        _validateGroupInfo(
            extension,
            groupId,
            amount,
            isFirstJoin,
            joinedGroupId,
            newTotal
        );
        _validateOwnerCapacity(extension, groupId, amount);
    }

    function _validateGroupInfo(
        address extension,
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

        ) = _groupManager.groupInfo(extension, groupId);

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
        if (newTotal > _groupManager.maxJoinAmount(extension))
            revert AmountExceedsAccountCap();

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
            if (_accountsHistory[extension][groupId].count() >= maxAccounts)
                revert GroupAccountsFull();
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
        uint256 groupId,
        uint256 amount
    ) internal view {
        address groupOwner = _group.ownerOf(groupId);
        uint256 ownerTotalJoined = _totalJoinedAmountByOwner(
            extension,
            groupOwner
        );
        uint256 ownerMaxVerifyCapacity = _groupManager.maxVerifyCapacityByOwner(
            extension,
            groupOwner
        );
        if (ownerTotalJoined + amount > ownerMaxVerifyCapacity) {
            revert OwnerCapacityExceeded();
        }
    }

    function _totalJoinedAmountByOwner(
        address extension,
        address owner
    ) internal view returns (uint256 total) {
        uint256[] memory ownerGroupIds = _groupManager.activeGroupIdsByOwner(
            extension,
            owner
        );
        for (uint256 i = 0; i < ownerGroupIds.length; i++) {
            total += _totalJoinedAmountHistoryByGroupId[extension][
                ownerGroupIds[i]
            ].latestValue();
        }
    }
}
