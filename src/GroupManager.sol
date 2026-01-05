// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupManager} from "./interface/IGroupManager.sol";
import {
    IERC721Enumerable
} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILOVE20Stake} from "@core/interfaces/ILOVE20Stake.sol";
import {ILOVE20Join} from "@core/interfaces/ILOVE20Join.sol";
import {ILOVE20Vote} from "@core/interfaces/ILOVE20Vote.sol";
import {IExtension} from "@extension/src/interface/IExtension.sol";
import {IGroupActionFactory} from "./interface/IGroupActionFactory.sol";
import {
    IExtensionFactory
} from "@extension/src/interface/IExtensionFactory.sol";
import {IExtensionCenter} from "@extension/src/interface/IExtensionCenter.sol";
import {IGroupAction} from "./interface/IGroupAction.sol";
import {
    EnumerableSet
} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {RoundHistoryString} from "@extension/src/lib/RoundHistoryString.sol";

contract GroupManager is IGroupManager {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;
    using RoundHistoryString for RoundHistoryString.History;

    uint256 public constant PRECISION = 1e18;

    IExtensionFactory internal _factory;
    IExtensionCenter internal _center;
    IERC721Enumerable internal _group;
    ILOVE20Stake internal _stake;
    ILOVE20Vote internal _vote;
    ILOVE20Join internal _join;

    address public FACTORY_ADDRESS;
    bool internal _initialized;
    // extension => groupId => GroupInfo
    mapping(address => mapping(uint256 => GroupInfo)) internal _groupInfo;
    // extension => groupId => descriptionHistory
    mapping(address => mapping(uint256 => RoundHistoryString.History))
        internal _descriptionHistory;
    // extension => activeGroupIds
    mapping(address => EnumerableSet.UintSet) internal _activeGroupIds;
    // extension => totalStaked
    mapping(address => uint256) internal _totalStaked;
    // tokenAddress => groupId => extensions
    mapping(address => mapping(uint256 => EnumerableSet.AddressSet))
        internal _extensionsByActivatedGroupId;
    // tokenAddress => extensions
    mapping(address => EnumerableSet.AddressSet)
        internal _extensionsWithGroupActivation;

    constructor() {}

    function initialize(address factory_) external {
        require(_initialized == false, "Already initialized");
        require(factory_ != address(0), "Invalid factory");

        FACTORY_ADDRESS = factory_;
        _factory = IExtensionFactory(factory_);
        _center = IExtensionCenter(
            IExtensionFactory(factory_).CENTER_ADDRESS()
        );
        _group = IERC721Enumerable(
            IGroupActionFactory(FACTORY_ADDRESS).GROUP_ADDRESS()
        );
        _stake = ILOVE20Stake(_center.stakeAddress());
        _vote = ILOVE20Vote(_center.voteAddress());
        _join = ILOVE20Join(_center.joinAddress());

        _initialized = true;
    }

    function activateGroup(
        address extension,
        uint256 groupId,
        string memory description,
        uint256 maxCapacity,
        uint256 minJoinAmount,
        uint256 maxJoinAmount_,
        uint256 maxAccounts_
    )
        external
        override
        onlyGroupOwner(groupId)
        onlyValidExtensionAndAutoInitialize(extension)
    {
        uint256 currentRound = _join.currentRound();

        _activateGroup(
            extension,
            groupId,
            description,
            maxCapacity,
            minJoinAmount,
            maxJoinAmount_,
            maxAccounts_,
            currentRound
        );

        IGroupAction ext = IGroupAction(extension);
        uint256 stakeAmount = ext.ACTIVATION_STAKE_AMOUNT();

        IERC20(ext.STAKE_TOKEN_ADDRESS()).safeTransferFrom(
            msg.sender,
            address(this),
            stakeAmount
        );

        emit ActivateGroup({
            tokenAddress: IExtension(extension).TOKEN_ADDRESS(),
            actionId: IExtension(extension).actionId(),
            round: currentRound,
            groupId: groupId,
            owner: msg.sender,
            stakeAmount: stakeAmount
        });
    }

    function deactivateGroup(
        address extension,
        uint256 groupId
    ) external override onlyGroupOwner(groupId) onlyValidExtension(extension) {
        address tokenAddress = IExtension(extension).TOKEN_ADDRESS();
        uint256 actionId = IExtension(extension).actionId();

        GroupInfo storage group = _groupInfo[extension][groupId];

        if (!group.isActive) revert GroupNotActive();

        uint256 currentRound = _join.currentRound();
        if (currentRound == group.activatedRound)
            revert CannotDeactivateInActivatedRound();

        group.isActive = false;
        group.deactivatedRound = currentRound;

        _activeGroupIds[extension].remove(groupId);

        _extensionsByActivatedGroupId[tokenAddress][groupId].remove(extension);
        if (_activeGroupIds[extension].length() == 0) {
            _extensionsWithGroupActivation[tokenAddress].remove(extension);
        }

        IGroupAction extConfig = IGroupAction(extension);
        uint256 stakedAmount = extConfig.ACTIVATION_STAKE_AMOUNT();
        _totalStaked[extension] -= stakedAmount;
        IERC20(extConfig.STAKE_TOKEN_ADDRESS()).safeTransfer(
            msg.sender,
            stakedAmount
        );

        emit DeactivateGroup({
            tokenAddress: tokenAddress,
            actionId: actionId,
            round: currentRound,
            groupId: groupId,
            owner: msg.sender,
            stakeAmount: stakedAmount
        });
    }

    function updateGroupInfo(
        address extension,
        uint256 groupId,
        string memory newDescription,
        uint256 newMaxCapacity,
        uint256 newMinJoinAmount,
        uint256 newMaxJoinAmount,
        uint256 newMaxAccounts
    ) external override onlyGroupOwner(groupId) onlyValidExtension(extension) {
        GroupInfo storage group = _groupInfo[extension][groupId];
        if (!group.isActive) revert GroupNotActive();

        uint256 currentRound = _join.currentRound();
        _updateGroupInfoFields(
            extension,
            groupId,
            newDescription,
            newMaxCapacity,
            newMinJoinAmount,
            newMaxJoinAmount,
            newMaxAccounts,
            currentRound
        );
    }

    function groupInfo(
        address extension,
        uint256 groupId
    )
        external
        view
        override
        returns (
            uint256 groupId_,
            string memory description,
            uint256 maxCapacity,
            uint256 minJoinAmount,
            uint256 maxJoinAmount_,
            uint256 maxAccounts,
            bool isActive,
            uint256 activatedRound,
            uint256 deactivatedRound
        )
    {
        GroupInfo storage info = _groupInfo[extension][groupId];
        return (
            info.groupId,
            info.description,
            info.maxCapacity,
            info.minJoinAmount,
            info.maxJoinAmount,
            info.maxAccounts,
            info.isActive,
            info.activatedRound,
            info.deactivatedRound
        );
    }

    function descriptionByRound(
        address extension,
        uint256 groupId,
        uint256 round
    ) external view override returns (string memory) {
        RoundHistoryString.History storage descHistory = _descriptionHistory[
            extension
        ][groupId];
        return descHistory.value(round);
    }

    function activeGroupIdsByOwner(
        address extension,
        address owner
    ) external view override returns (uint256[] memory) {
        uint256 nftBalance = _group.balanceOf(owner);
        uint256[] memory result = new uint256[](nftBalance);
        uint256 count;

        for (uint256 i; i < nftBalance; ) {
            uint256 gId = _group.tokenOfOwnerByIndex(owner, i);
            if (_groupInfo[extension][gId].isActive) {
                result[count] = gId;
                unchecked {
                    ++count;
                }
            }
            unchecked {
                ++i;
            }
        }

        if (count == 0) return new uint256[](0);

        assembly {
            mstore(result, count)
        }
        return result;
    }

    function activeGroupIds(
        address extension
    ) external view override returns (uint256[] memory) {
        return _activeGroupIds[extension].values();
    }

    function activeGroupIdsCount(
        address extension
    ) external view override returns (uint256) {
        return _activeGroupIds[extension].length();
    }

    function activeGroupIdsAtIndex(
        address extension,
        uint256 index
    ) external view override returns (uint256 groupId) {
        return _activeGroupIds[extension].at(index);
    }

    function isGroupActive(
        address extension,
        uint256 groupId
    ) external view override returns (bool) {
        return _groupInfo[extension][groupId].isActive;
    }

    function hasActiveGroups(
        address tokenAddress,
        address account
    ) external view override returns (bool) {
        uint256 balance = _group.balanceOf(account);

        for (uint256 i = 0; i < balance; ) {
            uint256 groupId = _group.tokenOfOwnerByIndex(account, i);
            if (
                _extensionsByActivatedGroupId[tokenAddress][groupId].length() >
                0
            ) {
                return true;
            }
            unchecked {
                ++i;
            }
        }

        return false;
    }

    function actionIdsByGroupIdCount(
        address tokenAddress,
        uint256 groupId
    ) external view override returns (uint256) {
        return _extensionsByActivatedGroupId[tokenAddress][groupId].length();
    }

    function actionIdsByGroupIdAtIndex(
        address tokenAddress,
        uint256 groupId,
        uint256 index
    ) external view override returns (uint256) {
        address extension = _extensionsByActivatedGroupId[tokenAddress][groupId]
            .at(index);
        return IExtension(extension).actionId();
    }

    function actionIds(
        address tokenAddress
    ) public view override returns (uint256[] memory) {
        address[] memory extensions = _extensionsWithGroupActivation[
            tokenAddress
        ].values();
        uint256[] memory actionIds_ = new uint256[](extensions.length);

        for (uint256 i; i < extensions.length; ) {
            actionIds_[i] = IExtension(extensions[i]).actionId();
            unchecked {
                ++i;
            }
        }

        return actionIds_;
    }

    function actionIdsCount(
        address tokenAddress
    ) external view override returns (uint256) {
        return _extensionsWithGroupActivation[tokenAddress].length();
    }

    function actionIdsAtIndex(
        address tokenAddress,
        uint256 index
    ) external view override returns (uint256) {
        address extension = _extensionsWithGroupActivation[tokenAddress].at(
            index
        );
        return IExtension(extension).actionId();
    }

    function maxJoinAmount(
        address extension
    ) public view override returns (uint256) {
        IGroupAction extConfig = IGroupAction(extension);
        address joinTokenAddress = extConfig.JOIN_TOKEN_ADDRESS();
        if (joinTokenAddress == address(0)) return 0;

        address tokenAddress = IExtension(extension).TOKEN_ADDRESS();
        uint256 actionId = IExtension(extension).actionId();
        uint256 round = _join.currentRound();

        uint256 totalVotes = _vote.votesNum(tokenAddress, round);
        if (totalVotes == 0) return 0;

        uint256 actionVotes = _vote.votesNumByActionId(
            tokenAddress,
            round,
            actionId
        );
        if (actionVotes == 0) return 0;

        uint256 voteRate = (actionVotes * PRECISION) / totalVotes;

        uint256 totalMinted = IERC20(joinTokenAddress).totalSupply();
        uint256 baseAmount = (totalMinted * extConfig.MAX_JOIN_AMOUNT_RATIO()) /
            PRECISION;
        return (baseAmount * voteRate) / PRECISION;
    }

    function maxVerifyCapacityByOwner(
        address extension,
        address owner
    ) public view override returns (uint256) {
        IGroupAction ext = IGroupAction(extension);
        address tokenAddress = IExtension(extension).TOKEN_ADDRESS();
        uint256 ownerGovVotes = _stake.validGovVotes(tokenAddress, owner);
        uint256 totalGovVotes = _stake.govVotesNum(tokenAddress);
        if (totalGovVotes == 0) return 0;

        uint256 totalMinted = IERC20(ext.JOIN_TOKEN_ADDRESS()).totalSupply();

        uint256 baseCapacity = (totalMinted * ownerGovVotes) / totalGovVotes;
        return (baseCapacity * ext.MAX_VERIFY_CAPACITY_FACTOR()) / PRECISION;
    }

    function totalStakedByOwner(
        address extension,
        address owner
    ) public view override returns (uint256) {
        IGroupAction ext = IGroupAction(extension);
        uint256 nftBalance = _group.balanceOf(owner);
        for (uint256 i; i < nftBalance; ) {
            uint256 gId = _group.tokenOfOwnerByIndex(owner, i);
            if (_groupInfo[extension][gId].isActive) {
                staked += ext.ACTIVATION_STAKE_AMOUNT();
            }
            unchecked {
                ++i;
            }
        }

        return staked;
    }

    function totalStaked(
        address extension
    ) public view override returns (uint256) {
        return _totalStaked[extension];
    }

    function actionIdsByGroupId(
        address tokenAddress,
        uint256 groupId
    ) public view override returns (uint256[] memory) {
        address[] memory extensions = _extensionsByActivatedGroupId[
            tokenAddress
        ][groupId].values();
        uint256[] memory actionIds_ = new uint256[](extensions.length);

        for (uint256 i; i < extensions.length; ) {
            actionIds_[i] = IExtension(extensions[i]).actionId();
            unchecked {
                ++i;
            }
        }

        return actionIds_;
    }

    modifier onlyGroupOwner(uint256 groupId) {
        if (_group.ownerOf(groupId) != msg.sender) revert OnlyGroupOwner();
        _;
    }

    modifier onlyValidExtensionAndAutoInitialize(address extension) {
        if (!_factory.exists(extension)) {
            revert NotRegisteredExtensionInFactory();
        }
        IExtension(extension).initializeIfNeeded();
        _;
    }
    modifier onlyValidExtension(address extension) {
        if (!_factory.exists(extension)) {
            revert NotRegisteredExtensionInFactory();
        }
        _;
    }

    function _updateGroupInfoFields(
        address extension,
        uint256 groupId,
        string memory description,
        uint256 maxCapacity,
        uint256 minJoinAmount,
        uint256 maxJoinAmount_,
        uint256 maxAccounts_,
        uint256 currentRound
    ) internal {
        if (maxJoinAmount_ != 0 && maxJoinAmount_ < minJoinAmount) {
            revert InvalidMinMaxJoinAmount();
        }

        GroupInfo storage group = _groupInfo[extension][groupId];
        group.description = description;
        group.maxCapacity = maxCapacity;
        group.minJoinAmount = minJoinAmount;
        group.maxJoinAmount = maxJoinAmount_;
        group.maxAccounts = maxAccounts_;

        _descriptionHistory[extension][groupId].record(
            currentRound,
            description
        );

        emit UpdateGroupInfo({
            tokenAddress: IExtension(extension).TOKEN_ADDRESS(),
            actionId: IExtension(extension).actionId(),
            round: currentRound,
            groupId: groupId,
            description: description,
            maxCapacity: maxCapacity,
            minJoinAmount: minJoinAmount,
            maxJoinAmount: maxJoinAmount_,
            maxAccounts: maxAccounts_
        });
    }

    function _activateGroup(
        address extension,
        uint256 groupId,
        string memory description,
        uint256 maxCapacity,
        uint256 minJoinAmount,
        uint256 maxJoinAmount_,
        uint256 maxAccounts_,
        uint256 currentRound
    ) internal {
        GroupInfo storage group = _groupInfo[extension][groupId];
        if (group.isActive) revert GroupAlreadyActivated();

        _updateGroupInfoFields(
            extension,
            groupId,
            description,
            maxCapacity,
            minJoinAmount,
            maxJoinAmount_,
            maxAccounts_,
            currentRound
        );

        group.groupId = groupId;
        group.activatedRound = currentRound;
        group.isActive = true;
        group.deactivatedRound = 0;

        IGroupAction ext = IGroupAction(extension);
        address tokenAddress = IExtension(extension).TOKEN_ADDRESS();
        uint256 stakeAmount = ext.ACTIVATION_STAKE_AMOUNT();

        _activeGroupIds[extension].add(groupId);
        _totalStaked[extension] += stakeAmount;
        _extensionsByActivatedGroupId[tokenAddress][groupId].add(extension);
        _extensionsWithGroupActivation[tokenAddress].add(extension);
    }
}
