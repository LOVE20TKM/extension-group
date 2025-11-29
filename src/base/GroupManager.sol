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

    ILOVE20Group internal immutable _groupAddress;
    uint256 public immutable minGovVoteRatioBps; // e.g.,  100 = 1%
    uint256 public immutable capacityMultiplier;
    uint256 public immutable stakingMultiplier;
    uint256 public immutable maxJoinAmountMultiplier;
    uint256 public immutable minJoinAmount;

    // ============ State ============

    mapping(uint256 => GroupInfo) internal _groups;
    uint256[] internal _allActivatedGroupIds;
    IERC20 internal _stakingToken;

    // ============ Constructor ============

    constructor(
        address factory_,
        address tokenAddress_,
        address groupAddress_,
        uint256 minGovVoteRatioBps_,
        uint256 capacityMultiplier_,
        uint256 stakingMultiplier_,
        uint256 maxJoinAmountMultiplier_,
        uint256 minJoinAmount_
    ) ExtensionCore(factory_, tokenAddress_) {
        _groupAddress = ILOVE20Group(groupAddress_);
        minGovVoteRatioBps = minGovVoteRatioBps_;
        capacityMultiplier = capacityMultiplier_;
        stakingMultiplier = stakingMultiplier_;
        maxJoinAmountMultiplier = maxJoinAmountMultiplier_;
        minJoinAmount = minJoinAmount_;
    }

    // ============ Modifiers ============

    modifier onlyGroupOwner(uint256 groupId) {
        if (_groupAddress.ownerOf(groupId) != msg.sender)
            revert OnlyGroupOwner();
        _;
    }

    modifier groupActive(uint256 groupId) {
        GroupInfo storage group = _groups[groupId];
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
        GroupInfo storage group = _groups[groupId];

        if (group.activatedRound != 0) revert GroupAlreadyActivated();
        if (stakedAmount == 0) revert InvalidGroupParameters();
        if (
            groupMaxJoinAmount != 0 && groupMaxJoinAmount < groupMinJoinAmount
        ) {
            revert InvalidGroupParameters();
        }

        address owner = _groupAddress.ownerOf(groupId);
        _checkCanActivateGroup(owner, stakedAmount);

        // Transfer stake
        if (address(_stakingToken) == address(0)) {
            _stakingToken = IERC20(tokenAddress);
        }
        _stakingToken.transferFrom(msg.sender, address(this), stakedAmount);

        // Initialize group
        uint256 stakedCapacity = stakedAmount * stakingMultiplier;
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

        _allActivatedGroupIds.push(groupId);

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

        GroupInfo storage group = _groups[groupId];
        uint256 newStakedAmount = group.stakedAmount + additionalStake;
        address owner = _groupAddress.ownerOf(groupId);

        _checkCanExpandGroup(owner, groupId, newStakedAmount);
        _stakingToken.transferFrom(msg.sender, address(this), additionalStake);

        group.stakedAmount = newStakedAmount;
        uint256 stakedCapacity = newStakedAmount * stakingMultiplier;
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
        GroupInfo storage group = _groups[groupId];

        if (group.activatedRound == 0) revert GroupNotFound();
        if (group.isDeactivated) revert GroupAlreadyDeactivated();

        uint256 currentRound = _join.currentRound();
        if (currentRound == group.activatedRound)
            revert CannotDeactivateInActivatedRound();

        group.isDeactivated = true;
        group.deactivatedRound = currentRound;

        uint256 stakedAmount = group.stakedAmount;
        _stakingToken.transfer(msg.sender, stakedAmount);

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

        GroupInfo storage group = _groups[groupId];
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

    function setGroupVerifier(
        uint256 groupId,
        address verifier
    ) public virtual onlyGroupOwner(groupId) groupActive(groupId) {
        _groups[groupId].verifier = verifier;
        emit GroupVerifierSet(groupId, verifier);
    }

    // ============ View Functions ============

    function groupAddress() external view returns (address) {
        return address(_groupAddress);
    }

    function getGroupInfo(
        uint256 groupId
    ) external view returns (GroupInfo memory) {
        return _groups[groupId];
    }

    function getGroupsByOwner(
        address owner
    ) external view returns (uint256[] memory) {
        uint256 nftBalance = _groupAddress.balanceOf(owner);
        uint256[] memory tempResult = new uint256[](nftBalance);
        uint256 count = 0;

        for (uint256 i = 0; i < nftBalance; i++) {
            uint256 groupId = _groupAddress.tokenOfOwnerByIndex(owner, i);
            if (_groups[groupId].activatedRound != 0) {
                tempResult[count++] = groupId;
            }
        }

        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = tempResult[i];
        }
        return result;
    }

    function getAllActivatedGroupIds()
        external
        view
        returns (uint256[] memory)
    {
        return _allActivatedGroupIds;
    }

    function isGroupActive(uint256 groupId) external view returns (bool) {
        GroupInfo storage group = _groups[groupId];
        return group.activatedRound != 0 && !group.isDeactivated;
    }

    function canVerify(
        address verifier,
        uint256 groupId
    ) public view returns (bool) {
        address owner = _groupAddress.ownerOf(groupId);
        return verifier == owner || verifier == _groups[groupId].verifier;
    }

    // ============ Capacity View Functions ============

    function calculateJoinMaxAmount() public view returns (uint256) {
        return
            ILOVE20Token(tokenAddress).totalSupply() / maxJoinAmountMultiplier;
    }

    function getMaxCapacityForOwner(
        address owner
    ) public view returns (uint256) {
        return _calculateMaxCapacityForOwner(owner);
    }

    function getTotalStakedByOwner(
        address owner
    ) public view returns (uint256) {
        return _getTotalStakedByOwner(owner);
    }

    function getExpandableInfo()
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
        (currentCapacity, currentStake) = _getTotalCapacityAndStakeByOwner(
            owner
        );
        maxCapacity = _calculateMaxCapacityForOwner(owner);
        maxStake = maxCapacity / stakingMultiplier;
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
            minGovVoteRatioBps *
            capacityMultiplier) / 1e4;
        uint256 minStake = minCapacity / stakingMultiplier;
        if (stakedAmount < minStake) revert InvalidGroupParameters();

        // Check owner has enough governance votes
        uint256 ownerGovVotes = _stake.validGovVotes(tokenAddress, owner);
        if (
            totalGovVotes == 0 ||
            (ownerGovVotes * 1e4) / totalGovVotes < minGovVoteRatioBps
        ) {
            revert InvalidGroupParameters();
        }

        // Check total stake doesn't exceed max
        uint256 maxCapacity = _calculateMaxCapacityForOwner(owner);
        uint256 maxStake = maxCapacity / stakingMultiplier;
        uint256 newTotalStake = _getTotalStakedByOwner(owner) + stakedAmount;
        if (newTotalStake > maxStake) revert InvalidGroupParameters();
    }

    function _checkCanExpandGroup(
        address owner,
        uint256 groupId,
        uint256 newStakedAmount
    ) internal view virtual {
        uint256 otherGroupsStake = _getTotalStakedByOwner(owner) -
            _groups[groupId].stakedAmount;
        uint256 maxCapacity = _calculateMaxCapacityForOwner(owner);
        uint256 maxStake = maxCapacity / stakingMultiplier;
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
            (totalMinted * ownerGovVotes * capacityMultiplier) / totalGovVotes;
    }

    function _getTotalStakedByOwner(
        address owner
    ) internal view returns (uint256 totalStaked) {
        uint256 nftBalance = _groupAddress.balanceOf(owner);
        for (uint256 i = 0; i < nftBalance; i++) {
            uint256 groupId = _groupAddress.tokenOfOwnerByIndex(owner, i);
            GroupInfo storage group = _groups[groupId];
            if (group.activatedRound != 0 && !group.isDeactivated) {
                totalStaked += group.stakedAmount;
            }
        }
    }

    function _getTotalCapacityAndStakeByOwner(
        address owner
    ) internal view returns (uint256 totalCapacity, uint256 totalStaked) {
        uint256 nftBalance = _groupAddress.balanceOf(owner);
        for (uint256 i = 0; i < nftBalance; i++) {
            uint256 groupId = _groupAddress.tokenOfOwnerByIndex(owner, i);
            GroupInfo storage group = _groups[groupId];
            if (group.activatedRound != 0 && !group.isDeactivated) {
                totalCapacity += group.capacity;
                totalStaked += group.stakedAmount;
            }
        }
    }
}
