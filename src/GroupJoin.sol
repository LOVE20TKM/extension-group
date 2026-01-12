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
import {
    EnumerableSet
} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {RoundHistoryUint256} from "@extension/src/lib/RoundHistoryUint256.sol";
import {
    RoundHistoryAddressSet
} from "@extension/src/lib/RoundHistoryAddressSet.sol";

using RoundHistoryUint256 for RoundHistoryUint256.History;
using RoundHistoryAddressSet for RoundHistoryAddressSet.Storage;
using EnumerableSet for EnumerableSet.UintSet;
using EnumerableSet for EnumerableSet.AddressSet;
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

    // Global state variables
    // groupId[]
    EnumerableSet.UintSet internal _gGroupIds;
    // account => groupId[]
    mapping(address => EnumerableSet.UintSet) internal _gGroupIdsByAccount;
    // tokenAddress => groupId[]
    mapping(address => EnumerableSet.UintSet) internal _gGroupIdsByTokenAddress;
    // tokenAddress => account => groupId[]
    mapping(address => mapping(address => EnumerableSet.UintSet))
        internal _gGroupIdsByTokenAddressByAccount;
    // tokenAddress => actionId => groupId[]
    mapping(address => mapping(uint256 => EnumerableSet.UintSet))
        internal _gGroupIdsByTokenAddressByActionId;

    // tokenAddress[]
    EnumerableSet.AddressSet internal _gTokenAddresses;
    // account => tokenAddress[]
    mapping(address => EnumerableSet.AddressSet)
        internal _gTokenAddressesByAccount;
    // groupId => tokenAddress[]
    mapping(uint256 => EnumerableSet.AddressSet)
        internal _gTokenAddressesByGroupId;
    // groupId => account => tokenAddress[]
    mapping(uint256 => mapping(address => EnumerableSet.AddressSet))
        internal _gTokenAddressesByGroupIdByAccount;

    // tokenAddress => actionId[]
    mapping(address => EnumerableSet.UintSet)
        internal _gActionIdsByTokenAddress;
    // tokenAddress => account => actionId[]
    mapping(address => mapping(address => EnumerableSet.UintSet))
        internal _gActionIdsByTokenAddressByAccount;
    // tokenAddress => groupId => actionId[]
    mapping(address => mapping(uint256 => EnumerableSet.UintSet))
        internal _gActionIdsByTokenAddressByGroupId;
    // tokenAddress => groupId => account => actionId[]
    mapping(address => mapping(uint256 => mapping(address => EnumerableSet.UintSet)))
        internal _gActionIdsByTokenAddressByGroupIdByAccount;

    // account[]
    EnumerableSet.AddressSet internal _gAccounts;
    // groupId => account[]
    mapping(uint256 => EnumerableSet.AddressSet) internal _gAccountsByGroupId;
    // tokenAddress => account[]
    mapping(address => EnumerableSet.AddressSet)
        internal _gAccountsByTokenAddress;
    // tokenAddress => groupId => account
    mapping(address => mapping(uint256 => EnumerableSet.AddressSet))
        internal _gAccountsByTokenAddressByGroupId;

    modifier onlyValidExtension(address extension) {
        if (!_factory.exists(extension)) {
            revert NotRegisteredExtensionInFactory();
        }
        if (!IExtension(extension).initialized()) {
            revert ExtensionNotInitialized();
        }
        _;
    }
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
        uint256 currentRound = _join.currentRound();
        uint256 joinedGroupId = _groupIdHistoryByAccount[extension][msg.sender]
            .latestValue();

        bool isFirstJoin = joinedGroupId == 0;
        _validateJoin(extension, groupId, amount, isFirstJoin, joinedGroupId);

        _increaseAmountHistory(
            extension,
            groupId,
            amount,
            currentRound,
            msg.sender
        );

        address tokenAddress = IExtension(extension).TOKEN_ADDRESS();
        uint256 actionId = IExtension(extension).actionId();
        if (isFirstJoin) {
            _joinedRoundByAccount[extension][msg.sender] = currentRound;
            _groupIdHistoryByAccount[extension][msg.sender].record(
                currentRound,
                groupId
            );
            _accountsHistory[extension][groupId].add(currentRound, msg.sender);
            _center.addAccount(
                tokenAddress,
                actionId,
                msg.sender,
                verificationInfos
            );
            _updateGlobalStateOnJoin(
                tokenAddress,
                actionId,
                groupId,
                msg.sender
            );
        } else if (verificationInfos.length > 0) {
            _center.updateVerificationInfo(
                tokenAddress,
                actionId,
                msg.sender,
                verificationInfos
            );
        }

        _transferJoinToken(extension, msg.sender, amount);

        emit Join({
            tokenAddress: tokenAddress,
            round: currentRound,
            actionId: actionId,
            groupId: groupId,
            account: msg.sender,
            amount: amount
        });
    }

    function exit(
        address extension
    ) external override nonReentrant onlyValidExtension(extension) {
        address tokenAddress = IExtension(extension).TOKEN_ADDRESS();
        uint256 actionId = IExtension(extension).actionId();
        uint256 groupId = _groupIdHistoryByAccount[extension][msg.sender]
            .latestValue();
        if (groupId == 0) revert NotJoinedAction();

        uint256 amount = _amountHistoryByAccount[extension][msg.sender]
            .latestValue();
        uint256 currentRound = _join.currentRound();

        _amountHistoryByAccount[extension][msg.sender].record(currentRound, 0);
        _groupIdHistoryByAccount[extension][msg.sender].record(currentRound, 0);

        _totalJoinedAmountHistoryByGroupId[extension][groupId].decrease(
            currentRound,
            amount
        );
        _totalJoinedAmountHistory[extension].decrease(currentRound, amount);

        delete _joinedRoundByAccount[extension][msg.sender];
        _accountsHistory[extension][groupId].remove(currentRound, msg.sender);
        _center.removeAccount(tokenAddress, actionId, msg.sender);
        _updateGlobalStateOnExit(
            extension,
            tokenAddress,
            actionId,
            groupId,
            msg.sender
        );

        address joinTokenAddress = IGroupAction(extension).JOIN_TOKEN_ADDRESS();
        IERC20 joinToken = IERC20(joinTokenAddress);

        joinToken.safeTransfer(msg.sender, amount);

        emit Exit({
            tokenAddress: tokenAddress,
            round: currentRound,
            actionId: actionId,
            groupId: groupId,
            account: msg.sender,
            amount: amount
        });
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
        uint256 round,
        address account
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
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        return
            _totalJoinedAmountHistoryByGroupId[extension][groupId].value(round);
    }

    function joinedAmount(
        address extension
    ) external view override returns (uint256) {
        return _totalJoinedAmountHistory[extension].latestValue();
    }

    function joinedAmountByRound(
        address extension,
        uint256 round
    ) external view override returns (uint256) {
        return _totalJoinedAmountHistory[extension].value(round);
    }

    function accountsByGroupIdByRound(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view override returns (address[] memory) {
        return _accountsHistory[extension][groupId].valuesByRound(round);
    }

    function accountsByGroupIdByRoundCount(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        return _accountsHistory[extension][groupId].countByRound(round);
    }

    function accountsByGroupIdByRoundAtIndex(
        address extension,
        uint256 round,
        uint256 groupId,
        uint256 index
    ) external view override returns (address) {
        return
            _accountsHistory[extension][groupId].atIndexByRound(index, round);
    }

    function joinedAmountByAccountByRound(
        address extension,
        uint256 round,
        address account
    ) external view override returns (uint256) {
        return _amountHistoryByAccount[extension][account].value(round);
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

    function _increaseAmountHistory(
        address extension,
        uint256 groupId,
        uint256 amount,
        uint256 currentRound,
        address account
    ) internal {
        _amountHistoryByAccount[extension][account].increase(
            currentRound,
            amount
        );
        _totalJoinedAmountHistoryByGroupId[extension][groupId].increase(
            currentRound,
            amount
        );
        _totalJoinedAmountHistory[extension].increase(currentRound, amount);
    }

    function _validateJoin(
        address extension,
        uint256 groupId,
        uint256 amount,
        bool isFirstJoin,
        uint256 joinedGroupId
    ) internal view {
        if (amount == 0) revert JoinAmountZero();

        // Check account's group membership (not based on GroupInfo)
        if (!isFirstJoin && joinedGroupId != groupId) {
            revert AlreadyInOtherGroup();
        }

        uint256 newTotal = _amountHistoryByAccount[extension][msg.sender]
            .latestValue() + amount;

        // All validations based on GroupInfo
        _validateGroupConstraints(
            extension,
            groupId,
            amount,
            isFirstJoin,
            newTotal
        );

        // Check extension-wide account limit
        uint256 extensionMaxJoinAmount = _groupManager.maxJoinAmount(extension);
        if (newTotal > extensionMaxJoinAmount) {
            revert AmountExceedsAccountCap();
        }

        // Owner-level constraints (not based on GroupInfo)
        _validateOwnerConstraints(extension, groupId, amount);
    }

    // All validations based on GroupInfo: fetch once and validate all constraints
    function _validateGroupConstraints(
        address extension,
        uint256 groupId,
        uint256 amount,
        bool isFirstJoin,
        uint256 newTotal
    ) internal view {
        // Fetch group info once
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

        // Validate group status
        if (!isActive) {
            revert CannotJoinDeactivatedGroup();
        }

        // Check group-specific account limit
        if (maxJoinAmount > 0 && newTotal > maxJoinAmount) {
            revert AmountExceedsAccountCap();
        }

        // Validate first join specific rules
        if (isFirstJoin) {
            // Check if group has reached max accounts
            if (maxAccounts > 0) {
                uint256 currentAccountCount = _accountsHistory[extension][
                    groupId
                ].count();
                if (currentAccountCount >= maxAccounts) {
                    revert GroupAccountsFull();
                }
            }

            // Check minimum join amount
            if (amount < minJoinAmount) {
                revert AmountBelowMinimum();
            }
        }

        // Validate group capacity
        if (maxCapacity > 0) {
            uint256 currentGroupTotal = _totalJoinedAmountHistoryByGroupId[
                extension
            ][groupId].latestValue();
            if (currentGroupTotal + amount > maxCapacity) {
                revert GroupCapacityExceeded();
            }
        }
    }

    // Owner-level validation: owner's total capacity across all groups
    function _validateOwnerConstraints(
        address extension,
        uint256 groupId,
        uint256 amount
    ) internal view {
        address groupOwner = _group.ownerOf(groupId);
        if (groupOwner == address(0)) {
            revert InvalidGroupId();
        }
        uint256 ownerTotalJoined = _totalJoinedAmountByGroupOwner(
            extension,
            groupOwner
        );
        uint256 ownerMaxCapacity = _groupManager.maxVerifyCapacityByOwner(
            extension,
            groupOwner
        );

        if (ownerTotalJoined + amount > ownerMaxCapacity) {
            revert OwnerCapacityExceeded();
        }
    }

    function totalJoinedAmountByGroupOwner(
        address extension,
        address owner
    ) external view override returns (uint256) {
        return _totalJoinedAmountByGroupOwner(extension, owner);
    }

    function _totalJoinedAmountByGroupOwner(
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
        return total;
    }

    function _updateGlobalStateOnJoin(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        address account
    ) internal {
        _gGroupIds.add(groupId);
        _gGroupIdsByAccount[account].add(groupId);
        _gGroupIdsByTokenAddress[tokenAddress].add(groupId);
        _gGroupIdsByTokenAddressByAccount[tokenAddress][account].add(groupId);
        _gGroupIdsByTokenAddressByActionId[tokenAddress][actionId].add(groupId);

        _gTokenAddresses.add(tokenAddress);
        _gTokenAddressesByAccount[account].add(tokenAddress);
        _gTokenAddressesByGroupId[groupId].add(tokenAddress);
        _gTokenAddressesByGroupIdByAccount[groupId][account].add(tokenAddress);

        _gActionIdsByTokenAddress[tokenAddress].add(actionId);
        _gActionIdsByTokenAddressByAccount[tokenAddress][account].add(actionId);
        _gActionIdsByTokenAddressByGroupId[tokenAddress][groupId].add(actionId);
        _gActionIdsByTokenAddressByGroupIdByAccount[tokenAddress][groupId][
            account
        ].add(actionId);

        _gAccounts.add(account);
        _gAccountsByGroupId[groupId].add(account);
        _gAccountsByTokenAddress[tokenAddress].add(account);
        _gAccountsByTokenAddressByGroupId[tokenAddress][groupId].add(account);
    }

    function _updateGlobalStateOnExit(
        address extension,
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        address account
    ) internal {
        _gActionIdsByTokenAddressByGroupIdByAccount[tokenAddress][groupId][
            account
        ].remove(actionId);

        _gActionIdsByTokenAddressByAccount[tokenAddress][account].remove(
            actionId
        );

        // check accountsByGroupIdCount if it is 0, then remove the groupId from the tokenAddress
        if (_accountsHistory[extension][groupId].count() == 0) {
            _gGroupIdsByTokenAddressByActionId[tokenAddress][actionId].remove(
                groupId
            );
            _gActionIdsByTokenAddressByGroupId[tokenAddress][groupId].remove(
                actionId
            );
            if (
                _gActionIdsByTokenAddressByGroupId[tokenAddress][groupId]
                    .length() == 0
            ) {
                _gTokenAddressesByGroupId[groupId].remove(tokenAddress);
                if (_gTokenAddressesByGroupId[groupId].length() == 0) {
                    _gGroupIds.remove(groupId);
                }
            }
        }

        if (
            _gActionIdsByTokenAddressByGroupIdByAccount[tokenAddress][groupId][
                account
            ].length() == 0
        ) {
            _gTokenAddressesByGroupIdByAccount[groupId][account].remove(
                tokenAddress
            );
            if (
                _gTokenAddressesByGroupIdByAccount[groupId][account].length() ==
                0
            ) {
                _gGroupIdsByAccount[account].remove(groupId);
                _gAccountsByGroupId[groupId].remove(account);

                if (_gGroupIdsByAccount[account].length() == 0) {
                    _gAccounts.remove(account);
                }
            }

            _gAccountsByTokenAddressByGroupId[tokenAddress][groupId].remove(
                account
            );
            if (
                _gAccountsByTokenAddressByGroupId[tokenAddress][groupId]
                    .length() == 0
            ) {
                _gGroupIdsByTokenAddress[tokenAddress].remove(groupId);
                if (_gGroupIdsByTokenAddress[tokenAddress].length() == 0) {
                    _gTokenAddresses.remove(tokenAddress);
                }
            }

            _gGroupIdsByTokenAddressByAccount[tokenAddress][account].remove(
                groupId
            );
            if (
                _gGroupIdsByTokenAddressByAccount[tokenAddress][account]
                    .length() == 0
            ) {
                _gAccountsByTokenAddress[tokenAddress].remove(account);
                _gTokenAddressesByAccount[account].remove(tokenAddress);
            }
        }

        if (_center.accountsCount(tokenAddress, actionId) == 0) {
            _gActionIdsByTokenAddress[tokenAddress].remove(actionId);
        }
    }

    // gGroupIds functions
    function gGroupIds() external view returns (uint256[] memory) {
        return _gGroupIds.values();
    }

    function gGroupIdsCount() external view returns (uint256) {
        return _gGroupIds.length();
    }

    function gGroupIdsAtIndex(uint256 index) external view returns (uint256) {
        return _gGroupIds.at(index);
    }

    // gGroupIdsByAccount functions
    function gGroupIdsByAccount(
        address account
    ) external view returns (uint256[] memory) {
        return _gGroupIdsByAccount[account].values();
    }

    function gGroupIdsByAccountCount(
        address account
    ) external view returns (uint256) {
        return _gGroupIdsByAccount[account].length();
    }

    function gGroupIdsByAccountAtIndex(
        address account,
        uint256 index
    ) external view returns (uint256) {
        return _gGroupIdsByAccount[account].at(index);
    }

    // gGroupIdsByTokenAddress functions
    function gGroupIdsByTokenAddress(
        address tokenAddress
    ) external view returns (uint256[] memory) {
        return _gGroupIdsByTokenAddress[tokenAddress].values();
    }

    function gGroupIdsByTokenAddressCount(
        address tokenAddress
    ) external view returns (uint256) {
        return _gGroupIdsByTokenAddress[tokenAddress].length();
    }

    function gGroupIdsByTokenAddressAtIndex(
        address tokenAddress,
        uint256 index
    ) external view returns (uint256) {
        return _gGroupIdsByTokenAddress[tokenAddress].at(index);
    }

    // gGroupIdsByTokenAddressByAccount functions
    function gGroupIdsByTokenAddressByAccount(
        address tokenAddress,
        address account
    ) external view returns (uint256[] memory) {
        return
            _gGroupIdsByTokenAddressByAccount[tokenAddress][account].values();
    }

    function gGroupIdsByTokenAddressByAccountCount(
        address tokenAddress,
        address account
    ) external view returns (uint256) {
        return
            _gGroupIdsByTokenAddressByAccount[tokenAddress][account].length();
    }

    function gGroupIdsByTokenAddressByAccountAtIndex(
        address tokenAddress,
        address account,
        uint256 index
    ) external view returns (uint256) {
        return
            _gGroupIdsByTokenAddressByAccount[tokenAddress][account].at(index);
    }

    function gGroupIdsByTokenAddressByActionId(
        address tokenAddress,
        uint256 actionId
    ) external view returns (uint256[] memory) {
        return
            _gGroupIdsByTokenAddressByActionId[tokenAddress][actionId].values();
    }

    function gGroupIdsByTokenAddressByActionIdCount(
        address tokenAddress,
        uint256 actionId
    ) external view returns (uint256) {
        return
            _gGroupIdsByTokenAddressByActionId[tokenAddress][actionId].length();
    }

    function gGroupIdsByTokenAddressByActionIdAtIndex(
        address tokenAddress,
        uint256 actionId,
        uint256 index
    ) external view returns (uint256) {
        return
            _gGroupIdsByTokenAddressByActionId[tokenAddress][actionId].at(
                index
            );
    }

    // gTokenAddresses functions
    function gTokenAddresses() external view returns (address[] memory) {
        return _gTokenAddresses.values();
    }

    function gTokenAddressesCount() external view returns (uint256) {
        return _gTokenAddresses.length();
    }

    function gTokenAddressesAtIndex(
        uint256 index
    ) external view returns (address) {
        return _gTokenAddresses.at(index);
    }

    // gTokenAddressesByAccount functions
    function gTokenAddressesByAccount(
        address account
    ) external view returns (address[] memory) {
        return _gTokenAddressesByAccount[account].values();
    }

    function gTokenAddressesByAccountCount(
        address account
    ) external view returns (uint256) {
        return _gTokenAddressesByAccount[account].length();
    }

    function gTokenAddressesByAccountAtIndex(
        address account,
        uint256 index
    ) external view returns (address) {
        return _gTokenAddressesByAccount[account].at(index);
    }

    // gTokenAddressesByGroupId functions
    function gTokenAddressesByGroupId(
        uint256 groupId
    ) external view returns (address[] memory) {
        return _gTokenAddressesByGroupId[groupId].values();
    }

    function gTokenAddressesByGroupIdCount(
        uint256 groupId
    ) external view returns (uint256) {
        return _gTokenAddressesByGroupId[groupId].length();
    }

    function gTokenAddressesByGroupIdAtIndex(
        uint256 groupId,
        uint256 index
    ) external view returns (address) {
        return _gTokenAddressesByGroupId[groupId].at(index);
    }

    // gTokenAddressesByGroupIdByAccount functions
    function gTokenAddressesByGroupIdByAccount(
        uint256 groupId,
        address account
    ) external view returns (address[] memory) {
        return _gTokenAddressesByGroupIdByAccount[groupId][account].values();
    }

    function gTokenAddressesByGroupIdByAccountCount(
        uint256 groupId,
        address account
    ) external view returns (uint256) {
        return _gTokenAddressesByGroupIdByAccount[groupId][account].length();
    }

    function gTokenAddressesByGroupIdByAccountAtIndex(
        uint256 groupId,
        address account,
        uint256 index
    ) external view returns (address) {
        return _gTokenAddressesByGroupIdByAccount[groupId][account].at(index);
    }

    // gActionIdsByTokenAddress functions
    function gActionIdsByTokenAddress(
        address tokenAddress
    ) external view returns (uint256[] memory) {
        return _gActionIdsByTokenAddress[tokenAddress].values();
    }

    function gActionIdsByTokenAddressCount(
        address tokenAddress
    ) external view returns (uint256) {
        return _gActionIdsByTokenAddress[tokenAddress].length();
    }

    function gActionIdsByTokenAddressAtIndex(
        address tokenAddress,
        uint256 index
    ) external view returns (uint256) {
        return _gActionIdsByTokenAddress[tokenAddress].at(index);
    }

    // gActionIdsByTokenAddressByAccount functions
    function gActionIdsByTokenAddressByAccount(
        address tokenAddress,
        address account
    ) external view returns (uint256[] memory) {
        return
            _gActionIdsByTokenAddressByAccount[tokenAddress][account].values();
    }

    function gActionIdsByTokenAddressByAccountCount(
        address tokenAddress,
        address account
    ) external view returns (uint256) {
        return
            _gActionIdsByTokenAddressByAccount[tokenAddress][account].length();
    }

    function gActionIdsByTokenAddressByAccountAtIndex(
        address tokenAddress,
        address account,
        uint256 index
    ) external view returns (uint256) {
        return
            _gActionIdsByTokenAddressByAccount[tokenAddress][account].at(index);
    }

    // gActionIdsByTokenAddressByGroupId functions
    function gActionIdsByTokenAddressByGroupId(
        address tokenAddress,
        uint256 groupId
    ) external view returns (uint256[] memory) {
        return
            _gActionIdsByTokenAddressByGroupId[tokenAddress][groupId].values();
    }

    function gActionIdsByTokenAddressByGroupIdCount(
        address tokenAddress,
        uint256 groupId
    ) external view returns (uint256) {
        return
            _gActionIdsByTokenAddressByGroupId[tokenAddress][groupId].length();
    }

    function gActionIdsByTokenAddressByGroupIdAtIndex(
        address tokenAddress,
        uint256 groupId,
        uint256 index
    ) external view returns (uint256) {
        return
            _gActionIdsByTokenAddressByGroupId[tokenAddress][groupId].at(index);
    }

    // gActionIdsByTokenAddressByGroupIdByAccount functions
    function gActionIdsByTokenAddressByGroupIdByAccount(
        address tokenAddress,
        uint256 groupId,
        address account
    ) external view returns (uint256[] memory) {
        return
            _gActionIdsByTokenAddressByGroupIdByAccount[tokenAddress][groupId][
                account
            ].values();
    }

    function gActionIdsByTokenAddressByGroupIdByAccountCount(
        address tokenAddress,
        uint256 groupId,
        address account
    ) external view returns (uint256) {
        return
            _gActionIdsByTokenAddressByGroupIdByAccount[tokenAddress][groupId][
                account
            ].length();
    }

    function gActionIdsByTokenAddressByGroupIdByAccountAtIndex(
        address tokenAddress,
        uint256 groupId,
        address account,
        uint256 index
    ) external view returns (uint256) {
        return
            _gActionIdsByTokenAddressByGroupIdByAccount[tokenAddress][groupId][
                account
            ].at(index);
    }

    // gAccounts functions
    function gAccounts() external view returns (address[] memory) {
        return _gAccounts.values();
    }

    function gAccountsCount() external view returns (uint256) {
        return _gAccounts.length();
    }

    function gAccountsAtIndex(uint256 index) external view returns (address) {
        return _gAccounts.at(index);
    }

    // gAccountsByGroupId functions
    function gAccountsByGroupId(
        uint256 groupId
    ) external view returns (address[] memory) {
        return _gAccountsByGroupId[groupId].values();
    }

    function gAccountsByGroupIdCount(
        uint256 groupId
    ) external view returns (uint256) {
        return _gAccountsByGroupId[groupId].length();
    }

    function gAccountsByGroupIdAtIndex(
        uint256 groupId,
        uint256 index
    ) external view returns (address) {
        return _gAccountsByGroupId[groupId].at(index);
    }

    // gAccountsByTokenAddress functions
    function gAccountsByTokenAddress(
        address tokenAddress
    ) external view returns (address[] memory) {
        return _gAccountsByTokenAddress[tokenAddress].values();
    }

    function gAccountsByTokenAddressCount(
        address tokenAddress
    ) external view returns (uint256) {
        return _gAccountsByTokenAddress[tokenAddress].length();
    }

    function gAccountsByTokenAddressAtIndex(
        address tokenAddress,
        uint256 index
    ) external view returns (address) {
        return _gAccountsByTokenAddress[tokenAddress].at(index);
    }

    // gAccountsByTokenAddressByGroupId functions
    function gAccountsByTokenAddressByGroupId(
        address tokenAddress,
        uint256 groupId
    ) external view returns (address[] memory) {
        return
            _gAccountsByTokenAddressByGroupId[tokenAddress][groupId].values();
    }

    function gAccountsByTokenAddressByGroupIdCount(
        address tokenAddress,
        uint256 groupId
    ) external view returns (uint256) {
        return
            _gAccountsByTokenAddressByGroupId[tokenAddress][groupId].length();
    }

    function gAccountsByTokenAddressByGroupIdAtIndex(
        address tokenAddress,
        uint256 groupId,
        uint256 index
    ) external view returns (address) {
        return
            _gAccountsByTokenAddressByGroupId[tokenAddress][groupId].at(index);
    }
}
