// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupManager} from "./interface/IGroupManager.sol";
import {ILOVE20Group} from "@group/interfaces/ILOVE20Group.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILOVE20Stake} from "@core/interfaces/ILOVE20Stake.sol";
import {ILOVE20Join} from "@core/interfaces/ILOVE20Join.sol";
import {ILOVE20Vote} from "@core/interfaces/ILOVE20Vote.sol";
import {ILOVE20SLToken} from "@core/interfaces/ILOVE20SLToken.sol";
import {ILOVE20STToken} from "@core/interfaces/ILOVE20STToken.sol";
import {ILOVE20Extension} from "@extension/src/interface/ILOVE20Extension.sol";
import {
    ILOVE20ExtensionFactory
} from "@extension/src/interface/ILOVE20ExtensionFactory.sol";
import {
    ILOVE20ExtensionGroupActionFactory
} from "./interface/ILOVE20ExtensionGroupActionFactory.sol";
import {
    ILOVE20ExtensionCenter
} from "@extension/src/interface/ILOVE20ExtensionCenter.sol";
import {
    ILOVE20ExtensionGroupAction
} from "./interface/ILOVE20ExtensionGroupAction.sol";
import {
    EnumerableSet
} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title GroupManager
/// @notice Singleton contract managing groups, keyed by extension address
/// @dev Users call directly, uses msg.sender for owner verification and transfers
contract GroupManager is IGroupManager {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    // ============ Immutables ============

    ILOVE20ExtensionGroupActionFactory internal _factory;
    ILOVE20ExtensionCenter internal _center;
    ILOVE20Group internal _group;
    ILOVE20Stake internal _stake;
    ILOVE20Vote internal _vote;
    ILOVE20Join internal _join;

    // ============ Constants ============

    /// @notice Precision constant (1e18) used for ratio and factor calculations
    uint256 public constant PRECISION = 1e18;

    // ============ State ============

    address internal _factoryAddress;
    bool internal _initialized;

    // extension, groupId => GroupInfo
    mapping(address => mapping(uint256 => GroupInfo)) internal _groupInfo;

    // extension => active groupIds set
    mapping(address => EnumerableSet.UintSet) internal _activeGroupIds;

    // extension => totalStaked
    mapping(address => uint256) internal _totalStaked;

    // actionFactory => tokenAddress => groupId => activated extensions set
    mapping(address => mapping(address => mapping(uint256 => EnumerableSet.AddressSet)))
        internal _extensionsByActivatedGroupId;

    // actionFactory => tokenAddress => extensions with at least one group activated
    mapping(address => mapping(address => EnumerableSet.AddressSet))
        internal _extensionsWithGroupActivation;

    // extension => (tokenAddress, actionId) 首次激活时的绑定关系
    mapping(address => TokenActionPair) internal _extensionTokenActionPair;

    // ============ Constructor ============

    constructor() {
        // Factory will be set via initialize()
    }

    // ============ Initialization ============

    /// @inheritdoc IGroupManager
    function initialize(address factory_) external {
        if (_initialized) revert AlreadyInitialized();
        if (factory_ == address(0)) revert InvalidFactory();

        _factoryAddress = factory_;
        _factory = ILOVE20ExtensionGroupActionFactory(factory_);
        _center = ILOVE20ExtensionCenter(_factory.center());
        _group = ILOVE20Group(_factory.GROUP_ADDRESS());
        _stake = ILOVE20Stake(_center.stakeAddress());
        _vote = ILOVE20Vote(_center.voteAddress());
        _join = ILOVE20Join(_center.joinAddress());

        _initialized = true;
    }

    // ============ Config Functions ============

    /// @inheritdoc IGroupManager
    function FACTORY_ADDRESS() external view override returns (address) {
        return _factoryAddress;
    }

    // Config addresses are accessed through the factory

    // ============ Internal Helpers ============

    function _getExtension(
        address tokenAddress,
        uint256 actionId
    ) internal view returns (address extension) {
        extension = _center.extension(tokenAddress, actionId);
        ILOVE20Extension extensionContract = ILOVE20Extension(extension);
        if (extension == address(0)) revert NotRegisteredExtension();
        try
            ILOVE20ExtensionFactory(extensionContract.factory()).exists(
                extension
            )
        returns (bool exists) {
            if (!exists) revert NotRegisteredExtensionInFactory();
        } catch {
            revert NotRegisteredExtensionInFactory();
        }
        return extension;
    }

    function _checkGroupOwner(uint256 groupId) internal view {
        if (_group.ownerOf(groupId) != msg.sender) revert OnlyGroupOwner();
    }

    function _checkAndSetExtensionTokenActionPair(
        address extension,
        address tokenAddress,
        uint256 actionId
    ) internal {
        TokenActionPair storage pair = _extensionTokenActionPair[extension];
        if (pair.tokenAddress != address(0)) {
            // Extension has been used before, check if (tokenAddress, actionId) matches
            if (
                pair.tokenAddress != tokenAddress || pair.actionId != actionId
            ) {
                revert ExtensionTokenActionMismatch();
            }
        } else {
            // First time using this extension, store the binding
            pair.tokenAddress = tokenAddress;
            pair.actionId = actionId;
        }
    }

    function _trackExtensionActivationAndInitialize(
        address actionFactory,
        address tokenAddress,
        uint256 groupId,
        address extension
    ) internal {
        _extensionsByActivatedGroupId[actionFactory][tokenAddress][groupId].add(
            extension
        );
        bool isFirstActivation = !_extensionsWithGroupActivation[actionFactory][
            tokenAddress
        ].contains(extension);
        _extensionsWithGroupActivation[actionFactory][tokenAddress].add(
            extension
        );

        // Initialize action if this is the first activation for this extension
        if (isFirstActivation) {
            // Call initializeAction() on the extension
            // This will join the action through LOVE20Join if not already joined
            try
                ILOVE20ExtensionGroupAction(extension).initializeAction()
            {} catch {}
        }
    }

    // ============ Write Functions ============

    function activateGroup(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        string memory description,
        uint256 maxCapacity,
        uint256 minJoinAmount,
        uint256 maxJoinAmount,
        uint256 maxAccounts_
    ) external override {
        address extension = _getExtension(tokenAddress, actionId);
        address actionFactory = ILOVE20Extension(extension).factory();
        _checkAndSetExtensionTokenActionPair(extension, tokenAddress, actionId);

        ILOVE20ExtensionGroupAction extConfig = ILOVE20ExtensionGroupAction(
            extension
        );
        _checkGroupOwner(groupId);

        GroupInfo storage group = _groupInfo[extension][groupId];

        if (group.isActive) revert GroupAlreadyActivated();
        if (maxJoinAmount != 0 && maxJoinAmount < minJoinAmount) {
            revert InvalidMinMaxJoinAmount();
        }

        // Transfer stake (all groups stake the same fixed amount)
        IERC20(extConfig.STAKE_TOKEN_ADDRESS()).safeTransferFrom(
            msg.sender,
            address(this),
            extConfig.ACTIVATION_STAKE_AMOUNT()
        );

        // Set group info
        group.groupId = groupId;
        group.description = description;
        group.maxCapacity = maxCapacity;
        group.minJoinAmount = minJoinAmount;
        group.maxJoinAmount = maxJoinAmount;
        group.maxAccounts = maxAccounts_;
        group.activatedRound = _join.currentRound();
        group.isActive = true;
        group.deactivatedRound = 0;

        _activeGroupIds[extension].add(groupId);
        _totalStaked[extension] += extConfig.ACTIVATION_STAKE_AMOUNT();

        // Track extension activation for this groupId and initialize if first activation
        _trackExtensionActivationAndInitialize(
            actionFactory,
            tokenAddress,
            groupId,
            extension
        );

        emit GroupActivate(
            tokenAddress,
            actionId,
            group.activatedRound,
            groupId,
            msg.sender,
            maxCapacity,
            maxAccounts_
        );
    }

    function deactivateGroup(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external override {
        address extension = _getExtension(tokenAddress, actionId);
        address actionFactory = ILOVE20Extension(extension).factory();
        _checkGroupOwner(groupId);

        GroupInfo storage group = _groupInfo[extension][groupId];

        if (group.activatedRound == 0) revert GroupNotFound();
        if (!group.isActive) revert GroupAlreadyDeactivated();

        uint256 currentRound = _join.currentRound();
        if (currentRound == group.activatedRound)
            revert CannotDeactivateInActivatedRound();

        group.isActive = false;
        group.deactivatedRound = currentRound;

        _activeGroupIds[extension].remove(groupId);

        // Remove extension from this groupId's activated extensions
        _extensionsByActivatedGroupId[actionFactory][tokenAddress][groupId]
            .remove(extension);
        // If this extension has no more active groups, remove from global set
        if (_activeGroupIds[extension].length() == 0) {
            _extensionsWithGroupActivation[actionFactory][tokenAddress].remove(
                extension
            );
        }

        // All activated groups stake the same fixed amount from config
        ILOVE20ExtensionGroupAction extConfig = ILOVE20ExtensionGroupAction(
            extension
        );
        uint256 stakedAmount = extConfig.ACTIVATION_STAKE_AMOUNT();
        _totalStaked[extension] -= stakedAmount;
        IERC20(extConfig.STAKE_TOKEN_ADDRESS()).safeTransfer(
            msg.sender,
            stakedAmount
        );

        emit GroupDeactivate(
            tokenAddress,
            actionId,
            currentRound,
            groupId,
            stakedAmount
        );
    }

    function updateGroupInfo(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        string memory newDescription,
        uint256 newMaxCapacity,
        uint256 newMinJoinAmount,
        uint256 newMaxJoinAmount,
        uint256 newMaxAccounts
    ) external override {
        address extension = _getExtension(tokenAddress, actionId);
        // Config is stored in extension, no need to validate here
        _checkGroupOwner(groupId);

        GroupInfo storage group = _groupInfo[extension][groupId];
        if (!group.isActive) revert GroupNotActive();

        if (newMaxJoinAmount != 0 && newMaxJoinAmount < newMinJoinAmount) {
            revert InvalidMinMaxJoinAmount();
        }

        group.description = newDescription;
        group.maxCapacity = newMaxCapacity;
        group.minJoinAmount = newMinJoinAmount;
        group.maxJoinAmount = newMaxJoinAmount;
        group.maxAccounts = newMaxAccounts;

        emit GroupInfoUpdate(
            tokenAddress,
            actionId,
            _join.currentRound(),
            groupId,
            newDescription,
            newMaxCapacity,
            newMinJoinAmount,
            newMaxJoinAmount,
            newMaxAccounts
        );
    }

    // ============ View Functions ============

    function groupInfo(
        address tokenAddress,
        uint256 actionId,
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
            uint256 maxJoinAmount,
            uint256 maxAccounts,
            bool isActive,
            uint256 activatedRound,
            uint256 deactivatedRound
        )
    {
        address extension = _center.extension(tokenAddress, actionId);
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

    function activeGroupIdsByOwner(
        address tokenAddress,
        uint256 actionId,
        address owner
    ) external view override returns (uint256[] memory) {
        address extension = _center.extension(tokenAddress, actionId);
        // Config is stored in extension, no need to check here

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

        // Resize array to valid length using assembly
        assembly {
            mstore(result, count)
        }
        return result;
    }

    function activeGroupIds(
        address tokenAddress,
        uint256 actionId
    ) external view override returns (uint256[] memory) {
        address extension = _center.extension(tokenAddress, actionId);
        return _activeGroupIds[extension].values();
    }

    function activeGroupIdsCount(
        address tokenAddress,
        uint256 actionId
    ) external view override returns (uint256) {
        address extension = _center.extension(tokenAddress, actionId);
        return _activeGroupIds[extension].length();
    }

    function activeGroupIdsAtIndex(
        address tokenAddress,
        uint256 actionId,
        uint256 index
    ) external view override returns (uint256 groupId) {
        address extension = _center.extension(tokenAddress, actionId);
        return _activeGroupIds[extension].at(index);
    }

    function isGroupActive(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external view override returns (bool) {
        address extension = _center.extension(tokenAddress, actionId);
        return _groupInfo[extension][groupId].isActive;
    }

    // ============ Capacity View Functions ============

    /// @dev Calculate max join amount using formula:
    /// maxJoinAmount = totalMinted * maxJoinAmountRatio * voteRate / PRECISION
    /// where totalMinted is the total supply of joinTokenAddress
    function calculateJoinMaxAmount(
        address tokenAddress,
        uint256 actionId
    ) public view override returns (uint256) {
        address extension = _center.extension(tokenAddress, actionId);
        ILOVE20ExtensionGroupAction extConfig = ILOVE20ExtensionGroupAction(
            extension
        );
        address joinTokenAddress = extConfig.JOIN_TOKEN_ADDRESS();
        if (joinTokenAddress == address(0)) return 0;

        // Get current round
        uint256 round = _join.currentRound();

        // Get total votes for this round
        uint256 totalVotes = _vote.votesNum(tokenAddress, round);
        if (totalVotes == 0) return 0;

        // Get votes for this action
        uint256 actionVotes = _vote.votesNumByActionId(
            tokenAddress,
            round,
            actionId
        );
        if (actionVotes == 0) return 0;

        // Calculate vote rate (using PRECISION for precision)
        uint256 voteRate = (actionVotes * PRECISION) / totalVotes;

        // Calculate max amount: totalMinted * maxJoinAmountRatio * voteRate / PRECISION
        // Use joinTokenAddress totalSupply (participating token total supply)
        // Split calculation to avoid overflow: (totalMinted * maxJoinAmountRatio / PRECISION) * voteRate / PRECISION
        uint256 totalMinted = IERC20(joinTokenAddress).totalSupply();
        uint256 baseAmount = (totalMinted * extConfig.MAX_JOIN_AMOUNT_RATIO()) /
            PRECISION;
        return (baseAmount * voteRate) / PRECISION;
    }

    function maxVerifyCapacityByOwner(
        address tokenAddress,
        uint256 actionId,
        address owner
    ) public view override returns (uint256) {
        address extension = _center.extension(tokenAddress, actionId);
        ILOVE20ExtensionGroupAction extConfig = ILOVE20ExtensionGroupAction(
            extension
        );
        return
            _calculateMaxVerifyCapacityByOwner(
                extension,
                owner,
                extConfig.MAX_VERIFY_CAPACITY_FACTOR()
            );
    }

    function totalStakedByActionIdByOwner(
        address tokenAddress,
        uint256 actionId,
        address owner
    ) public view override returns (uint256) {
        address extension = _center.extension(tokenAddress, actionId);
        // Config is stored in extension, no need to check here
        return _totalStakedByActionIdByOwner(extension, owner);
    }

    function totalStaked(
        address tokenAddress,
        uint256 actionId
    ) public view override returns (uint256) {
        address extension = _center.extension(tokenAddress, actionId);
        return _totalStaked[extension];
    }

    // ============ Extension Activation View Functions ============

    function actionIdsByGroupId(
        address actionFactory,
        address tokenAddress,
        uint256 groupId
    ) public view override returns (uint256[] memory) {
        address[] memory extensions = _extensionsByActivatedGroupId[
            actionFactory
        ][tokenAddress][groupId].values();
        uint256[] memory actionIds_ = new uint256[](extensions.length);

        for (uint256 i; i < extensions.length; ) {
            actionIds_[i] = _extensionTokenActionPair[extensions[i]].actionId;
            unchecked {
                ++i;
            }
        }

        return actionIds_;
    }

    function actionIdsByGroupIdCount(
        address actionFactory,
        address tokenAddress,
        uint256 groupId
    ) external view override returns (uint256) {
        return
            _extensionsByActivatedGroupId[actionFactory][tokenAddress][groupId]
                .length();
    }

    function actionIdsByGroupIdAtIndex(
        address actionFactory,
        address tokenAddress,
        uint256 groupId,
        uint256 index
    ) external view override returns (uint256) {
        address extension = _extensionsByActivatedGroupId[actionFactory][
            tokenAddress
        ][groupId].at(index);
        return _extensionTokenActionPair[extension].actionId;
    }

    function actionIds(
        address actionFactory,
        address tokenAddress
    ) public view override returns (uint256[] memory) {
        address[] memory extensions = _extensionsWithGroupActivation[
            actionFactory
        ][tokenAddress].values();
        uint256[] memory actionIds_ = new uint256[](extensions.length);

        for (uint256 i; i < extensions.length; ) {
            actionIds_[i] = _extensionTokenActionPair[extensions[i]].actionId;
            unchecked {
                ++i;
            }
        }

        return actionIds_;
    }

    function actionIdsCount(
        address actionFactory,
        address tokenAddress
    ) external view override returns (uint256) {
        return
            _extensionsWithGroupActivation[actionFactory][tokenAddress]
                .length();
    }

    function actionIdsAtIndex(
        address actionFactory,
        address tokenAddress,
        uint256 index
    ) external view override returns (uint256) {
        address extension = _extensionsWithGroupActivation[actionFactory][
            tokenAddress
        ].at(index);
        return _extensionTokenActionPair[extension].actionId;
    }

    /// @notice Get all voted group action extensions and their actionIds for a round
    function votedGroupActions(
        address actionFactory,
        address tokenAddress,
        uint256 round
    )
        external
        view
        override
        returns (uint256[] memory actionIds_, address[] memory extensions)
    {
        ILOVE20ExtensionFactory factory = ILOVE20ExtensionFactory(
            actionFactory
        );

        uint256 count = _vote.votedActionIdsCount(tokenAddress, round);
        if (count == 0) return (actionIds_, extensions);

        extensions = new address[](count);
        actionIds_ = new uint256[](count);
        uint256 valid;

        for (uint256 i; i < count; ) {
            uint256 aid = _vote.votedActionIdsAtIndex(tokenAddress, round, i);
            address ext = _center.extension(tokenAddress, aid);
            if (
                ext != address(0) &&
                _activeGroupIds[ext].length() > 0 &&
                factory.exists(ext)
            ) {
                extensions[valid] = ext;
                actionIds_[valid] = aid;
                unchecked {
                    ++valid;
                }
            }
            unchecked {
                ++i;
            }
        }

        if (valid == 0) return (actionIds_, extensions);

        // Resize arrays to valid length using assembly
        assembly {
            mstore(extensions, valid)
            mstore(actionIds_, valid)
        }
    }

    /// @notice Check if account has any active groups with actions
    /// @param actionFactory The action factory address
    /// @param tokenAddress The token address
    /// @param account The account to check
    /// @return True if account has at least one group with actions
    function hasActiveGroups(
        address actionFactory,
        address tokenAddress,
        address account
    ) external view override returns (bool) {
        uint256 balance = _group.balanceOf(account);

        for (uint256 i = 0; i < balance; ) {
            uint256 groupId = _group.tokenOfOwnerByIndex(account, i);
            if (
                _extensionsByActivatedGroupId[actionFactory][tokenAddress][
                    groupId
                ].length() > 0
            ) {
                return true;
            }
            unchecked {
                ++i;
            }
        }

        return false;
    }

    // ============ Internal Functions ============

    /// @dev Calculate max verify capacity for owner using formula:
    /// maxVerifyCapacity = ownerGovVotes / totalGovVotes * totalMinted * maxVerifyCapacityFactor / PRECISION
    function _calculateMaxVerifyCapacityByOwner(
        address extension,
        address owner,
        uint256 maxVerifyCapacityFactor
    ) internal view returns (uint256) {
        ILOVE20ExtensionGroupAction extConfig = ILOVE20ExtensionGroupAction(
            extension
        );
        address tokenAddress = extConfig.tokenAddress();
        uint256 ownerGovVotes = _stake.validGovVotes(tokenAddress, owner);
        uint256 totalGovVotes = _stake.govVotesNum(tokenAddress);
        if (totalGovVotes == 0) return 0;

        uint256 totalMinted = IERC20(extConfig.JOIN_TOKEN_ADDRESS())
            .totalSupply();

        uint256 baseCapacity = (totalMinted * ownerGovVotes) / totalGovVotes;
        return (baseCapacity * maxVerifyCapacityFactor) / PRECISION;
    }

    function _totalStakedByActionIdByOwner(
        address extension,
        address owner
    ) internal view returns (uint256 staked) {
        ILOVE20ExtensionGroupAction extConfig = ILOVE20ExtensionGroupAction(
            extension
        );
        // Config is stored in extension, no need to check here
        uint256 nftBalance = _group.balanceOf(owner);
        for (uint256 i; i < nftBalance; ) {
            uint256 gId = _group.tokenOfOwnerByIndex(owner, i);
            if (_groupInfo[extension][gId].isActive) {
                // All activated groups stake the same fixed amount
                staked += extConfig.ACTIVATION_STAKE_AMOUNT();
            }
            unchecked {
                ++i;
            }
        }
    }
}
