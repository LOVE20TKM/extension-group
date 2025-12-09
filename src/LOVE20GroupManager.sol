// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILOVE20GroupManager} from "./interface/ILOVE20GroupManager.sol";
import {ILOVE20Group} from "@group/interfaces/ILOVE20Group.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {ILOVE20Stake} from "@core/interfaces/ILOVE20Stake.sol";
import {ILOVE20Join} from "@core/interfaces/ILOVE20Join.sol";

/// @title LOVE20GroupManager
/// @notice Singleton contract managing groups, keyed by (tokenAddress, actionId)
/// @dev Users call directly, uses tx.origin for owner verification and transfers
contract LOVE20GroupManager is ILOVE20GroupManager {
    // ============ Immutables ============

    address public immutable override GROUP_ADDRESS;
    address public immutable override STAKE_ADDRESS;
    address public immutable override JOIN_ADDRESS;

    ILOVE20Group internal immutable _group;
    ILOVE20Stake internal immutable _stake;
    ILOVE20Join internal immutable _join;

    // ============ State ============

    /// @notice Config per (tokenAddress, actionId)
    mapping(address => mapping(uint256 => GroupConfig)) internal _configs;

    /// @notice Group info per (tokenAddress, actionId, groupId)
    mapping(address => mapping(uint256 => mapping(uint256 => GroupInfo)))
        internal _groupInfo;

    /// @notice Active group IDs per (tokenAddress, actionId)
    mapping(address => mapping(uint256 => uint256[])) internal _activeGroupIds;

    /// @notice Total staked per (tokenAddress, actionId)
    mapping(address => mapping(uint256 => uint256)) internal _totalStaked;

    // ============ Constructor ============

    constructor(
        address groupAddress_,
        address stakeAddress_,
        address joinAddress_
    ) {
        GROUP_ADDRESS = groupAddress_;
        STAKE_ADDRESS = stakeAddress_;
        JOIN_ADDRESS = joinAddress_;
        _group = ILOVE20Group(groupAddress_);
        _stake = ILOVE20Stake(stakeAddress_);
        _join = ILOVE20Join(joinAddress_);
    }

    // ============ Config Functions ============

    function setConfig(
        address tokenAddress,
        uint256 actionId,
        address stakeTokenAddress,
        uint256 minGovVoteRatioBps,
        uint256 capacityMultiplier,
        uint256 stakingMultiplier,
        uint256 maxJoinAmountMultiplier,
        uint256 minJoinAmount
    ) external override {
        if (_configs[tokenAddress][actionId].stakeTokenAddress != address(0))
            revert ConfigAlreadySet();

        _configs[tokenAddress][actionId] = GroupConfig({
            stakeTokenAddress: stakeTokenAddress,
            minGovVoteRatioBps: minGovVoteRatioBps,
            capacityMultiplier: capacityMultiplier,
            stakingMultiplier: stakingMultiplier,
            maxJoinAmountMultiplier: maxJoinAmountMultiplier,
            minJoinAmount: minJoinAmount
        });

        emit ConfigSet(tokenAddress, actionId, stakeTokenAddress);
    }

    function config(
        address tokenAddress,
        uint256 actionId
    ) external view override returns (GroupConfig memory) {
        return _configs[tokenAddress][actionId];
    }

    function isConfigSet(
        address tokenAddress,
        uint256 actionId
    ) external view override returns (bool) {
        return _configs[tokenAddress][actionId].stakeTokenAddress != address(0);
    }

    // ============ Internal Helpers ============

    function _getConfig(
        address tokenAddress,
        uint256 actionId
    ) internal view returns (GroupConfig storage) {
        GroupConfig storage cfg = _configs[tokenAddress][actionId];
        if (cfg.stakeTokenAddress == address(0)) revert ConfigNotSet();
        return cfg;
    }

    function _checkGroupOwner(uint256 groupId) internal view {
        if (_group.ownerOf(groupId) != tx.origin) revert OnlyGroupOwner();
    }

    // ============ Write Functions ============

    function activateGroup(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        string memory description,
        uint256 stakedAmount,
        uint256 groupMinJoinAmount,
        uint256 groupMaxJoinAmount
    ) external override returns (bool) {
        GroupConfig storage cfg = _getConfig(tokenAddress, actionId);
        _checkGroupOwner(groupId);

        GroupInfo storage group = _groupInfo[tokenAddress][actionId][groupId];

        if (group.isActive) revert GroupAlreadyActivated();
        if (stakedAmount == 0) revert ZeroStakeAmount();
        if (
            groupMaxJoinAmount != 0 && groupMaxJoinAmount < groupMinJoinAmount
        ) {
            revert InvalidMinMaxJoinAmount();
        }

        address owner = tx.origin;
        _checkCanActivateGroup(
            tokenAddress,
            actionId,
            cfg,
            owner,
            stakedAmount
        );

        IERC20(cfg.stakeTokenAddress).transferFrom(
            tx.origin,
            address(this),
            stakedAmount
        );

        {
            uint256 stakedCapacity = stakedAmount * cfg.stakingMultiplier;
            uint256 maxCapacity = _calculateMaxCapacityByOwner(
                tokenAddress,
                cfg,
                owner
            );
            group.capacity = stakedCapacity < maxCapacity
                ? stakedCapacity
                : maxCapacity;
        }
        uint256 currentRound = _join.currentRound();

        group.groupId = groupId;
        group.description = description;
        group.stakedAmount = stakedAmount;
        group.groupMinJoinAmount = groupMinJoinAmount;
        group.groupMaxJoinAmount = groupMaxJoinAmount;
        group.activatedRound = currentRound;

        group.isActive = true;
        group.deactivatedRound = 0;
        _activeGroupIds[tokenAddress][actionId].push(groupId);
        _totalStaked[tokenAddress][actionId] += stakedAmount;

        emit GroupActivate(
            tokenAddress,
            actionId,
            currentRound,
            groupId,
            owner,
            group.stakedAmount,
            group.capacity
        );
        return true;
    }

    function expandGroup(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 additionalStake
    ) external override returns (uint256 newStakedAmount, uint256 newCapacity) {
        GroupConfig storage cfg = _getConfig(tokenAddress, actionId);
        _checkGroupOwner(groupId);

        GroupInfo storage group = _groupInfo[tokenAddress][actionId][groupId];
        if (!group.isActive) revert GroupNotActive();
        if (additionalStake == 0) revert ZeroStakeAmount();

        newStakedAmount = group.stakedAmount + additionalStake;
        address owner = tx.origin;

        _checkCanExpandGroup(
            tokenAddress,
            actionId,
            cfg,
            owner,
            groupId,
            newStakedAmount
        );
        IERC20(cfg.stakeTokenAddress).transferFrom(
            tx.origin,
            address(this),
            additionalStake
        );

        group.stakedAmount = newStakedAmount;
        uint256 stakedCapacity = newStakedAmount * cfg.stakingMultiplier;
        uint256 maxCapacity = _calculateMaxCapacityByOwner(
            tokenAddress,
            cfg,
            owner
        );
        newCapacity = stakedCapacity < maxCapacity
            ? stakedCapacity
            : maxCapacity;
        group.capacity = newCapacity;
        _totalStaked[tokenAddress][actionId] += additionalStake;

        emit GroupExpand(
            tokenAddress,
            actionId,
            _join.currentRound(),
            groupId,
            additionalStake,
            newCapacity
        );

        return (newStakedAmount, newCapacity);
    }

    function deactivateGroup(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external override {
        GroupConfig storage cfg = _getConfig(tokenAddress, actionId);
        _checkGroupOwner(groupId);

        GroupInfo storage group = _groupInfo[tokenAddress][actionId][groupId];

        if (group.activatedRound == 0) revert GroupNotFound();
        if (!group.isActive) revert GroupAlreadyDeactivated();

        uint256 currentRound = _join.currentRound();
        if (currentRound == group.activatedRound)
            revert CannotDeactivateInActivatedRound();

        group.isActive = false;
        group.deactivatedRound = currentRound;

        _removeFromActiveGroupIds(tokenAddress, actionId, groupId);

        uint256 stakedAmount = group.stakedAmount;
        _totalStaked[tokenAddress][actionId] -= stakedAmount;
        IERC20(cfg.stakeTokenAddress).transfer(tx.origin, stakedAmount);

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
        uint256 newMinJoinAmount,
        uint256 newMaxJoinAmount
    ) external override {
        _getConfig(tokenAddress, actionId); // Validate config exists
        _checkGroupOwner(groupId);

        GroupInfo storage group = _groupInfo[tokenAddress][actionId][groupId];
        if (!group.isActive) revert GroupNotActive();

        if (newMaxJoinAmount != 0 && newMaxJoinAmount < newMinJoinAmount) {
            revert InvalidMinMaxJoinAmount();
        }

        group.description = newDescription;
        group.groupMinJoinAmount = newMinJoinAmount;
        group.groupMaxJoinAmount = newMaxJoinAmount;

        emit GroupInfoUpdate(
            tokenAddress,
            actionId,
            _join.currentRound(),
            groupId,
            newDescription,
            newMinJoinAmount,
            newMaxJoinAmount
        );
    }

    // ============ View Functions ============

    function groupInfo(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external view override returns (GroupInfo memory) {
        return _groupInfo[tokenAddress][actionId][groupId];
    }

    function activeGroupIdsByOwner(
        address tokenAddress,
        uint256 actionId,
        address owner
    ) external view override returns (uint256[] memory) {
        GroupConfig storage cfg = _configs[tokenAddress][actionId];
        if (cfg.stakeTokenAddress == address(0)) return new uint256[](0);

        uint256 nftBalance = _group.balanceOf(owner);
        uint256[] memory tempResult = new uint256[](nftBalance);
        uint256 count = 0;

        for (uint256 i = 0; i < nftBalance; i++) {
            uint256 gId = _group.tokenOfOwnerByIndex(owner, i);
            if (_groupInfo[tokenAddress][actionId][gId].isActive) {
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
        return _activeGroupIds[tokenAddress][actionId];
    }

    function activeGroupIdsCount(
        address tokenAddress,
        uint256 actionId
    ) external view override returns (uint256) {
        return _activeGroupIds[tokenAddress][actionId].length;
    }

    function activeGroupIdsAtIndex(
        address tokenAddress,
        uint256 actionId,
        uint256 index
    ) external view override returns (uint256 groupId) {
        return _activeGroupIds[tokenAddress][actionId][index];
    }

    function isGroupActive(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external view override returns (bool) {
        return _groupInfo[tokenAddress][actionId][groupId].isActive;
    }

    // ============ Capacity View Functions ============

    function calculateJoinMaxAmount(
        address tokenAddress,
        uint256 actionId
    ) public view override returns (uint256) {
        GroupConfig storage cfg = _configs[tokenAddress][actionId];
        if (cfg.stakeTokenAddress == address(0)) return 0;
        return
            ILOVE20Token(tokenAddress).totalSupply() /
            cfg.maxJoinAmountMultiplier;
    }

    function maxCapacityByOwner(
        address tokenAddress,
        uint256 actionId,
        address owner
    ) public view override returns (uint256) {
        GroupConfig storage cfg = _configs[tokenAddress][actionId];
        if (cfg.stakeTokenAddress == address(0)) return 0;
        return _calculateMaxCapacityByOwner(tokenAddress, cfg, owner);
    }

    function totalStakedByOwner(
        address tokenAddress,
        uint256 actionId,
        address owner
    ) public view override returns (uint256) {
        GroupConfig storage cfg = _configs[tokenAddress][actionId];
        if (cfg.stakeTokenAddress == address(0)) return 0;
        return _totalStakedByOwner(tokenAddress, actionId, owner);
    }

    function totalStaked(
        address tokenAddress,
        uint256 actionId
    ) public view override returns (uint256) {
        return _totalStaked[tokenAddress][actionId];
    }

    function expandableInfo(
        address tokenAddress,
        uint256 actionId,
        address owner
    )
        public
        view
        override
        returns (
            uint256 currentCapacity,
            uint256 maxCapacity,
            uint256 currentStake,
            uint256 maxStake,
            uint256 additionalStakeAllowed
        )
    {
        GroupConfig storage cfg = _configs[tokenAddress][actionId];
        if (cfg.stakeTokenAddress == address(0)) return (0, 0, 0, 0, 0);

        (currentCapacity, currentStake) = _totalCapacityAndStakeByOwner(
            tokenAddress,
            actionId,
            owner
        );
        maxCapacity = _calculateMaxCapacityByOwner(tokenAddress, cfg, owner);
        maxStake = maxCapacity / cfg.stakingMultiplier;
        if (maxStake > currentStake) {
            additionalStakeAllowed = maxStake - currentStake;
        }
    }

    // ============ Internal Functions ============

    function _checkCanActivateGroup(
        address tokenAddress,
        uint256 actionId,
        GroupConfig storage cfg,
        address owner,
        uint256 stakedAmount
    ) internal view {
        uint256 totalMinted = ILOVE20Token(tokenAddress).totalSupply();
        uint256 totalGovVotes = _stake.govVotesNum(tokenAddress);

        uint256 minCapacity = (totalMinted *
            cfg.minGovVoteRatioBps *
            cfg.capacityMultiplier) / 1e4;
        uint256 minStake = minCapacity / cfg.stakingMultiplier;
        if (stakedAmount < minStake) revert MinStakeNotMet();

        uint256 ownerGovVotes = _stake.validGovVotes(tokenAddress, owner);
        if (
            totalGovVotes == 0 ||
            (ownerGovVotes * 1e4) / totalGovVotes < cfg.minGovVoteRatioBps
        ) {
            revert InsufficientGovVotes();
        }

        uint256 maxCapacity = _calculateMaxCapacityByOwner(
            tokenAddress,
            cfg,
            owner
        );
        uint256 maxStake = maxCapacity / cfg.stakingMultiplier;
        uint256 newTotalStake = _totalStakedByOwner(
            tokenAddress,
            actionId,
            owner
        ) + stakedAmount;
        if (newTotalStake > maxStake) revert ExceedsMaxStake();
    }

    function _checkCanExpandGroup(
        address tokenAddress,
        uint256 actionId,
        GroupConfig storage cfg,
        address owner,
        uint256 groupId,
        uint256 newStakedAmount
    ) internal view {
        uint256 otherGroupsStake = _totalStakedByOwner(
            tokenAddress,
            actionId,
            owner
        ) - _groupInfo[tokenAddress][actionId][groupId].stakedAmount;
        uint256 maxCapacity = _calculateMaxCapacityByOwner(
            tokenAddress,
            cfg,
            owner
        );
        uint256 maxStake = maxCapacity / cfg.stakingMultiplier;
        if (otherGroupsStake + newStakedAmount > maxStake)
            revert ExceedsMaxStake();
    }

    function _calculateMaxCapacityByOwner(
        address tokenAddress,
        GroupConfig storage cfg,
        address owner
    ) internal view returns (uint256) {
        uint256 totalMinted = ILOVE20Token(tokenAddress).totalSupply();
        uint256 ownerGovVotes = _stake.validGovVotes(tokenAddress, owner);
        uint256 totalGovVotes = _stake.govVotesNum(tokenAddress);
        if (totalGovVotes == 0) return 0;
        return
            (totalMinted * ownerGovVotes * cfg.capacityMultiplier) /
            totalGovVotes;
    }

    function _totalStakedByOwner(
        address tokenAddress,
        uint256 actionId,
        address owner
    ) internal view returns (uint256 staked) {
        uint256 nftBalance = _group.balanceOf(owner);
        for (uint256 i = 0; i < nftBalance; i++) {
            uint256 gId = _group.tokenOfOwnerByIndex(owner, i);
            if (_groupInfo[tokenAddress][actionId][gId].isActive) {
                staked += _groupInfo[tokenAddress][actionId][gId].stakedAmount;
            }
        }
    }

    function _totalCapacityAndStakeByOwner(
        address tokenAddress,
        uint256 actionId,
        address owner
    ) internal view returns (uint256 capacity, uint256 staked) {
        uint256 nftBalance = _group.balanceOf(owner);
        for (uint256 i = 0; i < nftBalance; i++) {
            uint256 gId = _group.tokenOfOwnerByIndex(owner, i);
            GroupInfo storage group = _groupInfo[tokenAddress][actionId][gId];
            if (group.isActive) {
                capacity += group.capacity;
                staked += group.stakedAmount;
            }
        }
    }

    function _removeFromActiveGroupIds(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) internal {
        uint256[] storage ids = _activeGroupIds[tokenAddress][actionId];
        uint256 length = ids.length;
        for (uint256 i = 0; i < length; i++) {
            if (ids[i] == groupId) {
                ids[i] = ids[length - 1];
                ids.pop();
                break;
            }
        }
    }
}
