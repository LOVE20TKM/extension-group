// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILOVE20GroupManager} from "./interface/ILOVE20GroupManager.sol";
import {ILOVE20Group} from "@group/interfaces/ILOVE20Group.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {ILOVE20Stake} from "@core/interfaces/ILOVE20Stake.sol";
import {ILOVE20Join} from "@core/interfaces/ILOVE20Join.sol";
import {ILOVE20SLToken} from "@core/interfaces/ILOVE20SLToken.sol";
import {ILOVE20STToken} from "@core/interfaces/ILOVE20STToken.sol";
import {ILOVE20Extension} from "@extension/src/interface/ILOVE20Extension.sol";
import {
    ILOVE20ExtensionFactory
} from "@extension/src/interface/ILOVE20ExtensionFactory.sol";
import {
    ILOVE20ExtensionCenter
} from "@extension/src/interface/ILOVE20ExtensionCenter.sol";
import {
    EnumerableSet
} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title LOVE20GroupManager
/// @notice Singleton contract managing groups, keyed by extension address
/// @dev Users call directly, uses msg.sender for owner verification and transfers
contract LOVE20GroupManager is ILOVE20GroupManager {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    // ============ Immutables ============

    address public immutable override CENTER_ADDRESS;
    address public immutable override GROUP_ADDRESS;
    address public immutable override STAKE_ADDRESS;
    address public immutable override JOIN_ADDRESS;

    ILOVE20ExtensionCenter internal immutable _center;
    ILOVE20Group internal immutable _group;
    ILOVE20Stake internal immutable _stake;
    ILOVE20Join internal immutable _join;

    // ============ State ============

    // extension => Config
    mapping(address => Config) internal _configs;

    // extension, groupId => GroupInfo
    mapping(address => mapping(uint256 => GroupInfo)) internal _groupInfo;

    // extension => active groupIds set
    mapping(address => EnumerableSet.UintSet) internal _activeGroupIds;

    // extension => totalStaked
    mapping(address => uint256) internal _totalStaked;

    // tokenAddress => groupId => activated extensions set
    mapping(address => mapping(uint256 => EnumerableSet.AddressSet))
        internal _extensionsByActivatedGroupId;

    // tokenAddress => extensions with at least one group activated
    mapping(address => EnumerableSet.AddressSet)
        internal _extensionsWithGroupActivation;

    // extension => (tokenAddress, actionId) 首次激活时的绑定关系
    mapping(address => TokenActionPair) internal _extensionTokenActionPair;

    // ============ Constructor ============

    constructor(
        address centerAddress_,
        address groupAddress_,
        address stakeAddress_,
        address joinAddress_
    ) {
        CENTER_ADDRESS = centerAddress_;
        GROUP_ADDRESS = groupAddress_;
        STAKE_ADDRESS = stakeAddress_;
        JOIN_ADDRESS = joinAddress_;
        _center = ILOVE20ExtensionCenter(centerAddress_);
        _group = ILOVE20Group(groupAddress_);
        _stake = ILOVE20Stake(stakeAddress_);
        _join = ILOVE20Join(joinAddress_);
    }

    // ============ Config Functions ============

    function setConfig(
        address stakeTokenAddress,
        uint256 activationStakeAmount,
        uint256 maxJoinAmountMultiplier,
        uint256 verifyCapacityMultiplier
    ) external override {
        address extension = msg.sender;
        if (_configs[extension].stakeTokenAddress != address(0))
            revert ConfigAlreadySet();

        _configs[extension] = Config({
            stakeTokenAddress: stakeTokenAddress,
            activationStakeAmount: activationStakeAmount,
            maxJoinAmountMultiplier: maxJoinAmountMultiplier,
            verifyCapacityMultiplier: verifyCapacityMultiplier
        });

        emit ConfigSet(extension, stakeTokenAddress);
    }

    function config(
        address tokenAddress,
        uint256 actionId
    )
        external
        view
        override
        returns (
            address stakeTokenAddress,
            uint256 activationStakeAmount,
            uint256 maxJoinAmountMultiplier,
            uint256 verifyCapacityMultiplier
        )
    {
        address extension = _center.extension(tokenAddress, actionId);
        Config storage cfg = _configs[extension];
        return (
            cfg.stakeTokenAddress,
            cfg.activationStakeAmount,
            cfg.maxJoinAmountMultiplier,
            cfg.verifyCapacityMultiplier
        );
    }

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

    function _getConfig(
        address extension
    ) internal view returns (Config storage) {
        Config storage cfg = _configs[extension];
        if (cfg.stakeTokenAddress == address(0)) revert ConfigNotSet();
        return cfg;
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
    ) external override returns (bool) {
        address extension = _getExtension(tokenAddress, actionId);
        _checkAndSetExtensionTokenActionPair(extension, tokenAddress, actionId);

        Config storage cfg = _getConfig(extension);
        _checkGroupOwner(groupId);

        GroupInfo storage group = _groupInfo[extension][groupId];

        if (group.isActive) revert GroupAlreadyActivated();
        if (maxJoinAmount != 0 && maxJoinAmount < minJoinAmount) {
            revert InvalidMinMaxJoinAmount();
        }

        // Transfer stake (all groups stake the same fixed amount)
        IERC20(cfg.stakeTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            cfg.activationStakeAmount
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
        _totalStaked[extension] += cfg.activationStakeAmount;

        // Track extension activation for this groupId
        _extensionsByActivatedGroupId[tokenAddress][groupId].add(extension);
        // Track extension with group activation
        _extensionsWithGroupActivation[tokenAddress].add(extension);

        emit GroupActivate(
            tokenAddress,
            actionId,
            group.activatedRound,
            groupId,
            msg.sender,
            maxCapacity,
            maxAccounts_
        );
        return true;
    }

    function deactivateGroup(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external override {
        address extension = _getExtension(tokenAddress, actionId);
        Config storage cfg = _getConfig(extension);
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
        _extensionsByActivatedGroupId[tokenAddress][groupId].remove(extension);
        // If this extension has no more active groups, remove from global set
        if (_activeGroupIds[extension].length() == 0) {
            _extensionsWithGroupActivation[tokenAddress].remove(extension);
        }

        // All activated groups stake the same fixed amount from config
        uint256 stakedAmount = cfg.activationStakeAmount;
        _totalStaked[extension] -= stakedAmount;
        IERC20(cfg.stakeTokenAddress).safeTransfer(msg.sender, stakedAmount);

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
        _getConfig(extension); // Validate config exists
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
        Config storage cfg = _configs[extension];
        if (cfg.stakeTokenAddress == address(0)) return new uint256[](0);

        uint256 nftBalance = _group.balanceOf(owner);
        uint256[] memory tempResult = new uint256[](nftBalance);
        uint256 count = 0;

        for (uint256 i = 0; i < nftBalance; i++) {
            uint256 gId = _group.tokenOfOwnerByIndex(owner, i);
            if (_groupInfo[extension][gId].isActive) {
                tempResult[count++] = gId;
            }
        }

        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = tempResult[i];
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

    function calculateJoinMaxAmount(
        address tokenAddress,
        uint256 actionId
    ) public view override returns (uint256) {
        address extension = _center.extension(tokenAddress, actionId);
        Config storage cfg = _configs[extension];
        if (cfg.stakeTokenAddress == address(0)) return 0;
        return
            ILOVE20Token(tokenAddress).totalSupply() /
            cfg.maxJoinAmountMultiplier;
    }

    function maxVerifyCapacityByOwner(
        address tokenAddress,
        uint256 actionId,
        address owner
    ) public view override returns (uint256) {
        address extension = _center.extension(tokenAddress, actionId);
        Config storage cfg = _configs[extension];
        if (cfg.stakeTokenAddress == address(0)) return 0;
        return
            _calculateMaxVerifyCapacityByOwner(
                tokenAddress,
                owner,
                cfg.verifyCapacityMultiplier
            );
    }

    function totalStakedByActionIdByOwner(
        address tokenAddress,
        uint256 actionId,
        address owner
    ) public view override returns (uint256) {
        address extension = _center.extension(tokenAddress, actionId);
        Config storage cfg = _configs[extension];
        if (cfg.stakeTokenAddress == address(0)) return 0;
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
        address tokenAddress,
        uint256 groupId
    ) public view override returns (uint256[] memory) {
        address[] memory extensions = _extensionsByActivatedGroupId[
            tokenAddress
        ][groupId].values();
        uint256[] memory actionIds_ = new uint256[](extensions.length);

        for (uint256 i = 0; i < extensions.length; i++) {
            actionIds_[i] = _extensionTokenActionPair[extensions[i]].actionId;
        }

        return actionIds_;
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
        return _extensionTokenActionPair[extension].actionId;
    }

    function actionIds(
        address tokenAddress
    ) public view override returns (uint256[] memory) {
        address[] memory extensions = _extensionsWithGroupActivation[
            tokenAddress
        ].values();
        uint256[] memory actionIds_ = new uint256[](extensions.length);

        for (uint256 i = 0; i < extensions.length; i++) {
            actionIds_[i] = _extensionTokenActionPair[extensions[i]].actionId;
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
        return _extensionTokenActionPair[extension].actionId;
    }

    // ============ Internal Functions ============

    /// @dev Calculate max verify capacity for owner using formula:
    /// maxVerifyCapacity = ownerGovVotes / totalGovVotes * (totalMinted - slTokenAmount - stTokenReserve) * verifyCapacityMultiplier
    function _calculateMaxVerifyCapacityByOwner(
        address tokenAddress,
        address owner,
        uint256 verifyCapacityMultiplier
    ) internal view returns (uint256) {
        uint256 ownerGovVotes = _stake.validGovVotes(tokenAddress, owner);
        uint256 totalGovVotes = _stake.govVotesNum(tokenAddress);
        if (totalGovVotes == 0) return 0;

        uint256 totalMinted = ILOVE20Token(tokenAddress).totalSupply();

        // Get SL token amount (liquidity stake)
        address slAddress = ILOVE20Token(tokenAddress).slAddress();
        (uint256 tokenAmount, , uint256 feeTokenAmount, ) = ILOVE20SLToken(
            slAddress
        ).tokenAmounts();

        // Get ST token reserve (boost stake)
        address stAddress = ILOVE20Token(tokenAddress).stAddress();
        uint256 stTokenReserve = ILOVE20STToken(stAddress).reserve();

        // availableForCapacity = totalMinted - slTokenAmount - stTokenReserve
        uint256 availableForCapacity = totalMinted -
            tokenAmount -
            feeTokenAmount -
            stTokenReserve;

        uint256 baseCapacity = (availableForCapacity * ownerGovVotes) /
            totalGovVotes;
        return baseCapacity * verifyCapacityMultiplier;
    }

    function _totalStakedByActionIdByOwner(
        address extension,
        address owner
    ) internal view returns (uint256 staked) {
        Config storage cfg = _configs[extension];
        uint256 nftBalance = _group.balanceOf(owner);
        for (uint256 i = 0; i < nftBalance; i++) {
            uint256 gId = _group.tokenOfOwnerByIndex(owner, i);
            if (_groupInfo[extension][gId].isActive) {
                // All activated groups stake the same fixed amount
                staked += cfg.activationStakeAmount;
            }
        }
    }
}
