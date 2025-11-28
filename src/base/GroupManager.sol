// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILOVE20Group} from "@group/interfaces/ILOVE20Group.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGroupManager} from "../interface/base/IGroupManager.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {ILOVE20Stake} from "@core/interfaces/ILOVE20Stake.sol";
import {ExtensionCore} from "@extension/src/base/ExtensionCore.sol";

/// @title GroupManager
/// @notice Base contract for managing groups
/// @dev Integrates with LOVE20Group NFT for group identity
abstract contract GroupManager is ExtensionCore, IGroupManager {
    // ============================================
    // IMMUTABLE PARAMETERS
    // ============================================

    /// @notice Minimum governance vote ratio (e.g., 1e16 for 1%)
    uint256 public immutable minGovernanceVoteRatio;

    /// @notice Capacity multiplier
    uint256 public immutable capacityMultiplier;

    /// @notice Staking multiplier
    uint256 public immutable stakingMultiplier;

    /// @notice Max join amount multiplier
    uint256 public immutable maxJoinAmountMultiplier;

    /// @notice Minimum join amount
    uint256 public immutable minJoinAmount;

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Group NFT contract
    ILOVE20Group internal immutable _groupAddress;

    /// @notice Mapping from group ID to group info
    mapping(uint256 => GroupInfo) internal _groups;

    /// @notice List of all started group IDs (including stopped)
    uint256[] internal _allStartedGroupIds;

    /// @notice Staking token (initialized on first use)
    IERC20 internal _stakingToken;

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(
        address factory_,
        address tokenAddress_,
        address groupAddress_,
        uint256 minGovernanceVoteRatio_,
        uint256 capacityMultiplier_,
        uint256 stakingMultiplier_,
        uint256 maxJoinAmountMultiplier_,
        uint256 minJoinAmount_
    ) ExtensionCore(factory_, tokenAddress_) {
        _groupAddress = ILOVE20Group(groupAddress_);
        minGovernanceVoteRatio = minGovernanceVoteRatio_;
        capacityMultiplier = capacityMultiplier_;
        stakingMultiplier = stakingMultiplier_;
        maxJoinAmountMultiplier = maxJoinAmountMultiplier_;
        minJoinAmount = minJoinAmount_;
    }

    // ============================================
    // MODIFIERS
    // ============================================

    /// @dev Only group NFT owner can call
    modifier onlyGroupOwner(uint256 groupId) {
        if (_groupAddress.ownerOf(groupId) != msg.sender)
            revert OnlyGroupOwner();
        _;
    }

    /// @dev Only group owner or verifier can call
    modifier onlyGroupOwnerOrVerifier(uint256 groupId) {
        address owner = _groupAddress.ownerOf(groupId);
        if (msg.sender != owner && msg.sender != _groups[groupId].verifier) {
            revert OnlyGroupOwnerOrVerifier();
        }
        _;
    }

    /// @dev Group must be active
    modifier groupActive(uint256 groupId) {
        GroupInfo storage group = _groups[groupId];
        if (group.startedRound == 0 || group.isStopped) {
            revert GroupNotActive();
        }
        _;
    }

    // ============================================
    // GROUP MANAGEMENT
    // ============================================

    /// @inheritdoc IGroupManager
    function startGroup(
        uint256 groupId,
        string memory description,
        uint256 stakedAmount,
        uint256 groupMinJoinAmount,
        uint256 groupMaxJoinAmount
    ) public virtual onlyGroupOwner(groupId) returns (bool) {
        GroupInfo storage group = _groups[groupId];

        // Check if already started
        if (group.startedRound != 0) revert GroupAlreadyStarted();

        // Validate parameters
        if (stakedAmount == 0) revert InvalidGroupParameters();

        // Validate join amount constraints
        if (
            groupMaxJoinAmount != 0 && groupMaxJoinAmount < groupMinJoinAmount
        ) {
            revert InvalidGroupParameters();
        }

        // Capacity check
        address owner = _groupAddress.ownerOf(groupId);
        _checkCanStartGroup(owner, stakedAmount);

        // Transfer staking tokens
        if (address(_stakingToken) == address(0)) {
            _stakingToken = IERC20(tokenAddress);
        }
        _stakingToken.transferFrom(msg.sender, address(this), stakedAmount);

        // Calculate capacity
        uint256 capacity = _calculateGroupCapacity(owner, stakedAmount);
        uint256 currentRound = _join.currentRound();

        // Initialize group
        group.groupId = groupId;
        group.description = description;
        group.stakedAmount = stakedAmount;
        group.capacity = capacity;
        group.groupMinJoinAmount = groupMinJoinAmount;
        group.groupMaxJoinAmount = groupMaxJoinAmount;
        group.startedRound = currentRound;

        _allStartedGroupIds.push(groupId);

        emit GroupStarted(groupId, owner, stakedAmount, capacity, currentRound);
        return true;
    }

    /// @inheritdoc IGroupManager
    function expandGroup(
        uint256 groupId,
        uint256 additionalStake
    ) public virtual onlyGroupOwner(groupId) groupActive(groupId) {
        if (additionalStake == 0) revert InvalidGroupParameters();

        GroupInfo storage group = _groups[groupId];
        uint256 newStakedAmount = group.stakedAmount + additionalStake;

        address owner = _groupAddress.ownerOf(groupId);
        _checkCanExpandGroup(owner, newStakedAmount);

        _stakingToken.transferFrom(msg.sender, address(this), additionalStake);

        group.stakedAmount = newStakedAmount;
        uint256 newCapacity = _calculateGroupCapacity(owner, newStakedAmount);
        group.capacity = newCapacity;

        emit GroupExpanded(groupId, additionalStake, newCapacity);
    }

    /// @inheritdoc IGroupManager
    function stopGroup(uint256 groupId) public virtual onlyGroupOwner(groupId) {
        GroupInfo storage group = _groups[groupId];

        if (group.startedRound == 0) revert GroupNotFound();
        if (group.isStopped) revert GroupAlreadyStopped();

        uint256 currentRound = _join.currentRound();
        if (currentRound == group.startedRound)
            revert CannotStopInStartedRound();

        group.isStopped = true;
        group.stoppedRound = currentRound;

        uint256 stakedAmount = group.stakedAmount;
        _stakingToken.transfer(msg.sender, stakedAmount);

        emit GroupStopped(groupId, currentRound, stakedAmount);
    }

    /// @inheritdoc IGroupManager
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

    /// @inheritdoc IGroupManager
    function setGroupVerifier(
        uint256 groupId,
        address verifier
    ) public virtual onlyGroupOwner(groupId) groupActive(groupId) {
        _groups[groupId].verifier = verifier;
        emit GroupVerifierSet(groupId, verifier);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /// @inheritdoc IGroupManager
    function groupAddress() external view returns (address) {
        return address(_groupAddress);
    }

    /// @inheritdoc IGroupManager
    function getGroupInfo(
        uint256 groupId
    ) external view returns (GroupInfo memory) {
        return _groups[groupId];
    }

    /// @inheritdoc IGroupManager
    /// @dev Will revert if groupId NFT doesn't exist or has been burned
    function getGroupOwner(uint256 groupId) external view returns (address) {
        return _groupAddress.ownerOf(groupId);
    }

    /// @inheritdoc IGroupManager
    function getGroupsByOwner(
        address owner
    ) external view returns (uint256[] memory) {
        // First, get all NFTs owned by the address
        uint256 nftBalance = _groupAddress.balanceOf(owner);
        uint256[] memory tempResult = new uint256[](nftBalance);
        uint256 count = 0;

        // Check which owned NFTs have been started as groups
        for (uint256 i = 0; i < nftBalance; i++) {
            uint256 groupId = _groupAddress.tokenOfOwnerByIndex(owner, i);
            // Check if this group has been started
            if (_groups[groupId].startedRound != 0) {
                tempResult[count++] = groupId;
            }
        }

        // Resize array to actual count of started groups
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = tempResult[i];
        }

        return result;
    }

    /// @inheritdoc IGroupManager
    function getAllStartedGroupIds() external view returns (uint256[] memory) {
        return _allStartedGroupIds;
    }

    /// @inheritdoc IGroupManager
    function isGroupActive(uint256 groupId) external view returns (bool) {
        GroupInfo storage group = _groups[groupId];
        return group.startedRound != 0 && !group.isStopped;
    }

    /// @notice Check if address can verify a group
    function canVerify(
        address verifier,
        uint256 groupId
    ) public view returns (bool) {
        address owner = _groupAddress.ownerOf(groupId);
        return verifier == owner || verifier == _groups[groupId].verifier;
    }

    // ============================================
    // CAPACITY FUNCTIONS
    // ============================================

    /// @inheritdoc IGroupManager
    function calculateGroupCapacity(
        address owner,
        uint256 stakedAmount
    ) external view returns (uint256) {
        return _calculateGroupCapacity(owner, stakedAmount);
    }

    /// @inheritdoc IGroupManager
    function calculateJoinMaxAmount() public view returns (uint256) {
        uint256 totalMinted = ILOVE20Token(tokenAddress).totalSupply();
        return totalMinted / maxJoinAmountMultiplier;
    }

    /// @inheritdoc IGroupManager
    function checkCapacityAvailable(
        uint256 groupId,
        uint256 amount
    ) public view returns (bool) {
        GroupInfo memory group = _groups[groupId];
        return (group.totalJoinedAmount + amount <= group.capacity);
    }

    /// @inheritdoc IGroupManager
    function calculateStakeForCapacity(
        uint256 capacity
    ) public view returns (uint256) {
        return capacity / stakingMultiplier;
    }

    // ============================================
    // CAPACITY CALCULATION (INTERNAL)
    // ============================================

    /// @dev Check if owner can start a group with given stake
    function _checkCanStartGroup(
        address owner,
        uint256 stakedAmount
    ) internal view virtual {
        // Calculate minimum required stake
        uint256 totalMinted = ILOVE20Token(tokenAddress).totalSupply();
        uint256 minCapacity = (totalMinted *
            minGovernanceVoteRatio *
            capacityMultiplier) / 1e18;
        uint256 minStake = minCapacity / stakingMultiplier;

        if (stakedAmount < minStake) {
            revert InvalidGroupParameters();
        }

        // Check owner has enough governance votes
        uint256 ownerGovernanceVotes = _stake.validGovVotes(
            tokenAddress,
            owner
        );
        uint256 totalGovernanceVotes = ILOVE20Token(tokenAddress).totalSupply();

        if (
            (ownerGovernanceVotes * 1e18) / totalGovernanceVotes <
            minGovernanceVoteRatio
        ) {
            revert InvalidGroupParameters();
        }
    }

    /// @dev Check if owner can expand group
    function _checkCanExpandGroup(
        address owner,
        uint256 newStakedAmount
    ) internal view virtual {
        // Check doesn't exceed owner's capacity limit
        uint256 maxCapacity = _calculateMaxCapacityForOwner(owner);
        uint256 newCapacity = newStakedAmount * stakingMultiplier;

        if (newCapacity > maxCapacity) {
            revert InvalidGroupParameters();
        }
    }

    /// @dev Calculate group capacity based on staked amount
    function _calculateGroupCapacity(
        address owner,
        uint256 stakedAmount
    ) internal view virtual returns (uint256) {
        // Calculate capacity based on staking
        uint256 stakedCapacity = stakedAmount * stakingMultiplier;

        // Calculate max capacity based on owner's governance votes
        uint256 maxCapacity = _calculateMaxCapacityForOwner(owner);

        // Return minimum of the two
        return stakedCapacity < maxCapacity ? stakedCapacity : maxCapacity;
    }

    /// @dev Calculate max capacity for owner based on governance votes
    function _calculateMaxCapacityForOwner(
        address owner
    ) internal view returns (uint256) {
        uint256 totalMinted = ILOVE20Token(tokenAddress).totalSupply();
        uint256 ownerGovernanceVotes = _stake.validGovVotes(
            tokenAddress,
            owner
        );
        uint256 totalGovernanceVotes = ILOVE20Token(tokenAddress).totalSupply();

        return
            (totalMinted * ownerGovernanceVotes * capacityMultiplier) /
            totalGovernanceVotes;
    }
}
