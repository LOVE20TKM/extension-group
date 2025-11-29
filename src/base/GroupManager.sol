// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILOVE20Group} from "@group/interfaces/ILOVE20Group.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {ILOVE20Stake} from "@core/interfaces/ILOVE20Stake.sol";
import {ExtensionCore} from "@extension/src/base/ExtensionCore.sol";
import {IGroupManager} from "../interface/base/IGroupManager.sol";

/// @title GroupManager
/// @notice Base contract for managing groups with LOVE20Group NFT integration
abstract contract GroupManager is ExtensionCore, IGroupManager {
    // ============ Immutables ============

    address public immutable GROUP_ADDRESS;
    address public immutable STAKE_TOKEN_ADDRESS;
    uint256 public immutable MIN_GOV_VOTE_RATIO_BPS; // e.g.,  100 = 1%
    uint256 public immutable CAPACITY_MULTIPLIER;
    uint256 public immutable STAKING_MULTIPLIER;
    uint256 public immutable MAX_JOIN_AMOUNT_MULTIPLIER;
    uint256 public immutable MIN_JOIN_AMOUNT;

    // ============ State ============

    // groupId => GroupInfo
    mapping(uint256 => GroupInfo) internal _groupInfo;
    uint256[] internal _activeGroupIds;

    // ============ Constructor ============

    constructor(
        address factory_,
        address tokenAddress_,
        address groupAddress_,
        address stakeTokenAddress_,
        uint256 minGovVoteRatioBps_,
        uint256 capacityMultiplier_,
        uint256 stakingMultiplier_,
        uint256 maxJoinAmountMultiplier_,
        uint256 minJoinAmount_
    ) ExtensionCore(factory_, tokenAddress_) {
        GROUP_ADDRESS = groupAddress_;
        STAKE_TOKEN_ADDRESS = stakeTokenAddress_;
        MIN_GOV_VOTE_RATIO_BPS = minGovVoteRatioBps_;
        CAPACITY_MULTIPLIER = capacityMultiplier_;
        STAKING_MULTIPLIER = stakingMultiplier_;
        MAX_JOIN_AMOUNT_MULTIPLIER = maxJoinAmountMultiplier_;
        MIN_JOIN_AMOUNT = minJoinAmount_;
    }

    // ============ Modifiers ============

    modifier onlyGroupOwner(uint256 groupId) {
        if (ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId) != msg.sender)
            revert OnlyGroupOwner();
        _;
    }

    modifier groupActive(uint256 groupId) {
        GroupInfo storage group = _groupInfo[groupId];
        if (group.activatedRound == 0 || group.isDeactivated)
            revert GroupNotActive();
        _;
    }

    // ============ Write Functions ============

    function activateGroup(
        uint256 groupId,
        string memory description,
        uint256 stakedAmount,
        uint256 groupMinJoinAmount,
        uint256 groupMaxJoinAmount
    ) public virtual onlyGroupOwner(groupId) returns (bool) {
        GroupInfo storage group = _groupInfo[groupId];

        if (group.activatedRound != 0) revert GroupAlreadyActivated();
        if (stakedAmount == 0) revert InvalidGroupParameters();
        if (
            groupMaxJoinAmount != 0 && groupMaxJoinAmount < groupMinJoinAmount
        ) {
            revert InvalidGroupParameters();
        }

        address owner = ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId);
        _checkCanActivateGroup(owner, stakedAmount);

        // Transfer stake
        IERC20(STAKE_TOKEN_ADDRESS).transferFrom(
            msg.sender,
            address(this),
            stakedAmount
        );

        // Initialize group
        uint256 stakedCapacity = stakedAmount * STAKING_MULTIPLIER;
        uint256 maxCapacity = _calculateMaxCapacityForOwner(owner);
        uint256 capacity = stakedCapacity < maxCapacity
            ? stakedCapacity
            : maxCapacity;
        uint256 currentRound = _join.currentRound();

        group.groupId = groupId;
        group.description = description;
        group.stakedAmount = stakedAmount;
        group.capacity = capacity;
        group.groupMinJoinAmount = groupMinJoinAmount;
        group.groupMaxJoinAmount = groupMaxJoinAmount;
        group.activatedRound = currentRound;

        _activeGroupIds.push(groupId);

        emit GroupActivated(
            groupId,
            owner,
            stakedAmount,
            capacity,
            currentRound
        );
        return true;
    }

    function expandGroup(
        uint256 groupId,
        uint256 additionalStake
    ) public virtual onlyGroupOwner(groupId) groupActive(groupId) {
        if (additionalStake == 0) revert InvalidGroupParameters();

        GroupInfo storage group = _groupInfo[groupId];
        uint256 newStakedAmount = group.stakedAmount + additionalStake;
        address owner = ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId);

        _checkCanExpandGroup(owner, groupId, newStakedAmount);
        IERC20(STAKE_TOKEN_ADDRESS).transferFrom(
            msg.sender,
            address(this),
            additionalStake
        );

        group.stakedAmount = newStakedAmount;
        uint256 stakedCapacity = newStakedAmount * STAKING_MULTIPLIER;
        uint256 maxCapacity = _calculateMaxCapacityForOwner(owner);
        uint256 newCapacity = stakedCapacity < maxCapacity
            ? stakedCapacity
            : maxCapacity;
        group.capacity = newCapacity;

        emit GroupExpanded(groupId, additionalStake, newCapacity);
    }

    function deactivateGroup(
        uint256 groupId
    ) public virtual onlyGroupOwner(groupId) {
        GroupInfo storage group = _groupInfo[groupId];

        if (group.activatedRound == 0) revert GroupNotFound();
        if (group.isDeactivated) revert GroupAlreadyDeactivated();

        uint256 currentRound = _join.currentRound();
        if (currentRound == group.activatedRound)
            revert CannotDeactivateInActivatedRound();

        group.isDeactivated = true;
        group.deactivatedRound = currentRound;

        uint256 stakedAmount = group.stakedAmount;
        IERC20(STAKE_TOKEN_ADDRESS).transfer(msg.sender, stakedAmount);

        emit GroupDeactivated(groupId, currentRound, stakedAmount);
    }

    function updateGroupInfo(
        uint256 groupId,
        string memory newDescription,
        uint256 newMinJoinAmount,
        uint256 newMaxJoinAmount
    ) public virtual onlyGroupOwner(groupId) groupActive(groupId) {
        if (newMaxJoinAmount != 0 && newMaxJoinAmount < newMinJoinAmount) {
            revert InvalidGroupParameters();
        }

        GroupInfo storage group = _groupInfo[groupId];
        group.description = newDescription;
        group.groupMinJoinAmount = newMinJoinAmount;
        group.groupMaxJoinAmount = newMaxJoinAmount;

        emit GroupInfoUpdated(
            groupId,
            newDescription,
            newMinJoinAmount,
            newMaxJoinAmount
        );
    }

    function setGroupDelegatedVerifier(
        uint256 groupId,
        address delegatedVerifier
    ) public virtual onlyGroupOwner(groupId) groupActive(groupId) {
        _groupInfo[groupId].delegatedVerifier = delegatedVerifier;
        emit GroupDelegatedVerifierSet(groupId, delegatedVerifier);
    }

    // ============ View Functions ============

    function groupInfo(
        uint256 groupId
    ) external view returns (GroupInfo memory) {
        return _groupInfo[groupId];
    }

    function activeGroupIdsByOwner(
        address owner
    ) external view returns (uint256[] memory) {
        uint256 nftBalance = ILOVE20Group(GROUP_ADDRESS).balanceOf(owner);
        uint256[] memory tempResult = new uint256[](nftBalance);
        uint256 count = 0;

        for (uint256 i = 0; i < nftBalance; i++) {
            uint256 groupId = ILOVE20Group(GROUP_ADDRESS).tokenOfOwnerByIndex(
                owner,
                i
            );
            if (_groupInfo[groupId].activatedRound != 0) {
                tempResult[count++] = groupId;
            }
        }

        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = tempResult[i];
        }
        return result;
    }

    function activeGroupIds() external view returns (uint256[] memory) {
        return _activeGroupIds;
    }
    function activeGroupIdsCount() external view returns (uint256) {
        return _activeGroupIds.length;
    }
    function activeGroupIdsAtIndex(
        uint256 index
    ) external view returns (uint256 groupId) {
        return _activeGroupIds[index];
    }

    function isGroupActive(uint256 groupId) external view returns (bool) {
        GroupInfo storage group = _groupInfo[groupId];
        return group.activatedRound != 0 && !group.isDeactivated;
    }

    function canVerify(
        address account,
        uint256 groupId
    ) public view returns (bool) {
        address owner = ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId);
        return
            account == owner ||
            account == _groupInfo[groupId].delegatedVerifier;
    }

    // ============ Capacity View Functions ============

    function calculateJoinMaxAmount() public view returns (uint256) {
        return
            ILOVE20Token(tokenAddress).totalSupply() /
            MAX_JOIN_AMOUNT_MULTIPLIER;
    }

    function maxCapacityForOwner(address owner) public view returns (uint256) {
        return _calculateMaxCapacityForOwner(owner);
    }

    function totalStakedByOwner(address owner) public view returns (uint256) {
        return _totalStakedByOwner(owner);
    }

    function expandableInfo()
        public
        view
        returns (
            uint256 currentCapacity,
            uint256 maxCapacity,
            uint256 currentStake,
            uint256 maxStake,
            uint256 additionalStakeAllowed
        )
    {
        address owner = msg.sender;
        (currentCapacity, currentStake) = _totalCapacityAndStakeByOwner(owner);
        maxCapacity = _calculateMaxCapacityForOwner(owner);
        maxStake = maxCapacity / STAKING_MULTIPLIER;
        if (maxStake > currentStake) {
            additionalStakeAllowed = maxStake - currentStake;
        }
    }

    // ============ Internal Functions ============

    function _checkCanActivateGroup(
        address owner,
        uint256 stakedAmount
    ) internal view virtual {
        uint256 totalMinted = ILOVE20Token(tokenAddress).totalSupply();
        uint256 totalGovVotes = _stake.govVotesNum(tokenAddress);

        // Check minimum stake
        uint256 minCapacity = (totalMinted *
            MIN_GOV_VOTE_RATIO_BPS *
            CAPACITY_MULTIPLIER) / 1e4;
        uint256 minStake = minCapacity / STAKING_MULTIPLIER;
        if (stakedAmount < minStake) revert InvalidGroupParameters();

        // Check owner has enough governance votes
        uint256 ownerGovVotes = _stake.validGovVotes(tokenAddress, owner);
        if (
            totalGovVotes == 0 ||
            (ownerGovVotes * 1e4) / totalGovVotes < MIN_GOV_VOTE_RATIO_BPS
        ) {
            revert InvalidGroupParameters();
        }

        // Check total stake doesn't exceed max
        uint256 maxCapacity = _calculateMaxCapacityForOwner(owner);
        uint256 maxStake = maxCapacity / STAKING_MULTIPLIER;
        uint256 newTotalStake = _totalStakedByOwner(owner) + stakedAmount;
        if (newTotalStake > maxStake) revert InvalidGroupParameters();
    }

    function _checkCanExpandGroup(
        address owner,
        uint256 groupId,
        uint256 newStakedAmount
    ) internal view virtual {
        uint256 otherGroupsStake = _totalStakedByOwner(owner) -
            _groupInfo[groupId].stakedAmount;
        uint256 maxCapacity = _calculateMaxCapacityForOwner(owner);
        uint256 maxStake = maxCapacity / STAKING_MULTIPLIER;
        if (otherGroupsStake + newStakedAmount > maxStake)
            revert InvalidGroupParameters();
    }

    function _calculateMaxCapacityForOwner(
        address owner
    ) internal view returns (uint256) {
        uint256 totalMinted = ILOVE20Token(tokenAddress).totalSupply();
        uint256 ownerGovVotes = _stake.validGovVotes(tokenAddress, owner);
        uint256 totalGovVotes = _stake.govVotesNum(tokenAddress);
        if (totalGovVotes == 0) return 0;
        return
            (totalMinted * ownerGovVotes * CAPACITY_MULTIPLIER) / totalGovVotes;
    }

    function _totalStakedByOwner(
        address owner
    ) internal view returns (uint256 totalStaked) {
        uint256 nftBalance = ILOVE20Group(GROUP_ADDRESS).balanceOf(owner);
        for (uint256 i = 0; i < nftBalance; i++) {
            uint256 groupId = ILOVE20Group(GROUP_ADDRESS).tokenOfOwnerByIndex(
                owner,
                i
            );
            GroupInfo storage group = _groupInfo[groupId];
            if (group.activatedRound != 0 && !group.isDeactivated) {
                totalStaked += group.stakedAmount;
            }
        }
    }

    function _totalCapacityAndStakeByOwner(
        address owner
    ) internal view returns (uint256 totalCapacity, uint256 totalStaked) {
        uint256 nftBalance = ILOVE20Group(GROUP_ADDRESS).balanceOf(owner);
        for (uint256 i = 0; i < nftBalance; i++) {
            uint256 groupId = ILOVE20Group(GROUP_ADDRESS).tokenOfOwnerByIndex(
                owner,
                i
            );
            GroupInfo storage group = _groupInfo[groupId];
            if (group.activatedRound != 0 && !group.isDeactivated) {
                totalCapacity += group.capacity;
                totalStaked += group.stakedAmount;
            }
        }
    }
}
