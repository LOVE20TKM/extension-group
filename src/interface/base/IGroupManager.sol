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

    event GroupDescriptionUpdated(
        uint256 indexed groupId,
        string newDescription
    );

    event GroupVerifierSet(uint256 indexed groupId, address indexed verifier);

    // ============================================
    // STRUCTS
    // ============================================

    /// @notice Group information structure
    /// @dev owner is not stored, retrieved via _groupNFT.ownerOf(groupId)
    struct GroupInfo {
        uint256 groupId;
        address verifier;
        string description;
        uint256 stakedAmount;
        uint256 capacity;
        uint256 minJoinAmount;
        uint256 maxJoinAmount; // 0 = no limit
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
        uint256 minJoinAmount,
        uint256 maxJoinAmount
    ) external returns (bool);

    /// @notice Expand group capacity
    function expandGroup(uint256 groupId, uint256 additionalStake) external;

    /// @notice Stop a group
    function stopGroup(uint256 groupId) external;

    /// @notice Update group description
    function updateGroupDescription(
        uint256 groupId,
        string memory newDescription
    ) external;

    /// @notice Set group verifier
    function setGroupVerifier(uint256 groupId, address verifier) external;

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /// @notice Get Group NFT contract address
    function groupNFT() external view returns (address);

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
}
