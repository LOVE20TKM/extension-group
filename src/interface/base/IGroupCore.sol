// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupCore {
    // ============ Errors ============

    error GroupNotFound();
    error GroupAlreadyActivated();
    error GroupAlreadyDeactivated();
    error GroupNotActive();
    error ZeroStakeAmount();
    error InvalidMinMaxJoinAmount();
    error InsufficientGovVotes();
    error ExceedsMaxStake();
    error MinStakeNotMet();
    error CannotDeactivateInActivatedRound();
    error OnlyGroupOwner();

    // ============ Events ============

    event GroupActivate(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 indexed groupId,
        address owner,
        uint256 stakedAmount,
        uint256 capacity
    );
    event GroupExpand(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 indexed groupId,
        uint256 additionalStake,
        uint256 newCapacity
    );
    event GroupDeactivate(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 indexed groupId,
        uint256 returnedStake
    );
    event GroupInfoUpdate(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 indexed groupId,
        string newDescription,
        uint256 newMinJoinAmount,
        uint256 newMaxJoinAmount
    );
    // ============ Structs ============

    /// @notice Group information (owner retrieved via NFT ownerOf)
    struct GroupInfo {
        uint256 groupId;
        string description;
        uint256 stakedAmount;
        uint256 capacity;
        uint256 groupMinJoinAmount;
        uint256 groupMaxJoinAmount; // 0 = no limit
        uint256 totalJoinedAmount;
        bool isActive;
        uint256 activatedRound; // 0 = never activated
        uint256 deactivatedRound; // 0 = never deactivated
    }

    // ============ Write Functions ============

    function activateGroup(
        uint256 groupId,
        string memory description,
        uint256 stakedAmount,
        uint256 groupMinJoinAmount,
        uint256 groupMaxJoinAmount
    ) external returns (bool);

    function expandGroup(uint256 groupId, uint256 additionalStake) external;

    function deactivateGroup(uint256 groupId) external;

    function updateGroupInfo(
        uint256 groupId,
        string memory newDescription,
        uint256 newMinJoinAmount,
        uint256 newMaxJoinAmount
    ) external;

    // ============ View Functions ============

    function groupInfo(
        uint256 groupId
    ) external view returns (GroupInfo memory);
    function activeGroupIdsByOwner(
        address owner
    ) external view returns (uint256[] memory);
    function activeGroupIds() external view returns (uint256[] memory);
    function activeGroupIdsCount() external view returns (uint256);
    function activeGroupIdsAtIndex(
        uint256 index
    ) external view returns (uint256 groupId);

    function isGroupActive(uint256 groupId) external view returns (bool);

    // --- Config Parameters (immutable) ---
    function GROUP_ADDRESS() external view returns (address);
    function STAKE_TOKEN_ADDRESS() external view returns (address);
    function MIN_GOV_VOTE_RATIO_BPS() external view returns (uint256);
    function CAPACITY_MULTIPLIER() external view returns (uint256);
    function STAKING_MULTIPLIER() external view returns (uint256);
    function MAX_JOIN_AMOUNT_MULTIPLIER() external view returns (uint256);
    function MIN_JOIN_AMOUNT() external view returns (uint256);

    // --- Capacity ---
    function calculateJoinMaxAmount() external view returns (uint256);
    function maxCapacityByOwner(address owner) external view returns (uint256);
    function totalStakedByOwner(address owner) external view returns (uint256);
    function totalStaked() external view returns (uint256);
    function expandableInfo(
        address owner
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
