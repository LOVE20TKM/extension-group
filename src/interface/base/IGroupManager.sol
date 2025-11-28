// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupManager {
    // ============================================
    // ERRORS
    // ============================================

    error GroupNotFound();
    error GroupAlreadyStarted();
    error GroupAlreadyStopped();
    error OnlyGroupOwner();
    error OnlyGroupOwnerOrVerifier();
    error GroupNotActive();
    error InvalidGroupParameters();
    error CannotStopInStartedRound();
    error NotGroupNFTOwner();

    // ============================================
    // EVENTS
    // ============================================

    event GroupStarted(
        uint256 indexed groupId,
        address indexed owner,
        uint256 stakedAmount,
        uint256 capacity,
        uint256 round
    );

    event GroupExpanded(
        uint256 indexed groupId,
        uint256 additionalStake,
        uint256 newCapacity
    );

    event GroupStopped(
        uint256 indexed groupId,
        uint256 round,
        uint256 returnedStake
    );

    event GroupInfoUpdated(
        uint256 indexed groupId,
        string newDescription,
        uint256 newMinJoinAmount,
        uint256 newMaxJoinAmount
    );

    event GroupVerifierSet(uint256 indexed groupId, address indexed verifier);

    // ============================================
    // STRUCTS
    // ============================================

    /// @notice Group information structure
    /// @dev owner is not stored, retrieved via _groupAddress.ownerOf(groupId)
    struct GroupInfo {
        uint256 groupId;
        address verifier;
        string description;
        uint256 stakedAmount;
        uint256 capacity;
        uint256 groupMinJoinAmount;
        uint256 groupMaxJoinAmount; // 0 = no limit
        uint256 totalJoinedAmount;
        bool isStopped;
        uint256 startedRound; // 0 = not started
        uint256 stoppedRound; // 0 = not stopped
    }

    // ============================================
    // FUNCTIONS
    // ============================================

    /// @notice Start a group (must own Group NFT)
    function startGroup(
        uint256 groupId,
        string memory description,
        uint256 stakedAmount,
        uint256 groupMinJoinAmount,
        uint256 groupMaxJoinAmount
    ) external returns (bool);

    /// @notice Expand group capacity
    function expandGroup(uint256 groupId, uint256 additionalStake) external;

    /// @notice Stop a group
    function stopGroup(uint256 groupId) external;

    /// @notice Update group info (description, min/max join amounts)
    function updateGroupInfo(
        uint256 groupId,
        string memory newDescription,
        uint256 newMinJoinAmount,
        uint256 newMaxJoinAmount
    ) external;

    /// @notice Set group verifier
    function setGroupVerifier(uint256 groupId, address verifier) external;

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /// @notice Get Group NFT contract address
    function groupAddress() external view returns (address);

    /// @notice Get group information
    function getGroupInfo(
        uint256 groupId
    ) external view returns (GroupInfo memory);

    /// @notice Get group owner (from NFT)
    function getGroupOwner(uint256 groupId) external view returns (address);

    /// @notice Get all groups owned by an address
    function getGroupsByOwner(
        address owner
    ) external view returns (uint256[] memory);

    /// @notice Get all started group IDs
    function getAllStartedGroupIds() external view returns (uint256[] memory);

    /// @notice Check if group is active
    function isGroupActive(uint256 groupId) external view returns (bool);

    /// @notice Check if address can verify a group
    function canVerify(
        address verifier,
        uint256 groupId
    ) external view returns (bool);

    // ============================================
    // CAPACITY FUNCTIONS
    // ============================================

    /// @notice Get minimum governance vote ratio
    function minGovernanceVoteRatio() external view returns (uint256);

    /// @notice Get capacity multiplier
    function capacityMultiplier() external view returns (uint256);

    /// @notice Get staking multiplier
    function stakingMultiplier() external view returns (uint256);

    /// @notice Get max join amount multiplier
    function maxJoinAmountMultiplier() external view returns (uint256);

    /// @notice Get minimum join amount
    function minJoinAmount() external view returns (uint256);

    /// @notice Calculate group capacity
    function calculateGroupCapacity(
        address owner,
        uint256 stakedAmount
    ) external view returns (uint256);

    /// @notice Calculate max amount for join
    function calculateJoinMaxAmount() external view returns (uint256);

    /// @notice Check if capacity is available for amount
    function checkCapacityAvailable(
        uint256 groupId,
        uint256 amount
    ) external view returns (bool);

    /// @notice Calculate stake required for a given capacity
    function calculateStakeForCapacity(
        uint256 capacity
    ) external view returns (uint256);

    /// @notice Get max capacity for owner based on governance votes
    function getMaxCapacityForOwner(
        address owner
    ) external view returns (uint256);

    /// @notice Get minimum stake required to start a group
    function getMinStakeToStart() external view returns (uint256);

    /// @notice Get remaining capacity for a group
    function getRemainingCapacity(
        uint256 groupId
    ) external view returns (uint256);

    /// @notice Get expandable info for a group
    /// @return currentCapacity Current group capacity
    /// @return maxCapacity Max capacity based on owner's governance votes
    /// @return currentStake Current staked amount
    /// @return maxStake Max stake allowed (to reach maxCapacity)
    /// @return additionalStakeAllowed Additional stake that can be added
    function getExpandableInfo(
        uint256 groupId
    )
        external
        view
        returns (
            uint256 currentCapacity,
            uint256 maxCapacity,
            uint256 currentStake,
            uint256 maxStake,
            uint256 additionalStakeAllowed
        );
}
