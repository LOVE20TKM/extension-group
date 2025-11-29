// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupManager {
    // ============ Errors ============

    error GroupNotFound();
    error GroupAlreadyActivated();
    error GroupAlreadyDeactivated();
    error GroupNotActive();
    error InvalidGroupParameters();
    error CannotDeactivateInActivatedRound();
    error OnlyGroupOwner();

    // ============ Events ============

    event GroupActivated(
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
    event GroupDeactivated(
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

    // ============ Structs ============

    /// @notice Group information (owner retrieved via NFT ownerOf)
    struct GroupInfo {
        uint256 groupId;
        address verifier;
        string description;
        uint256 stakedAmount;
        uint256 capacity;
        uint256 groupMinJoinAmount;
        uint256 groupMaxJoinAmount; // 0 = no limit
        uint256 totalJoinedAmount;
        bool isDeactivated;
        uint256 activatedRound; // 0 = not activated
        uint256 deactivatedRound; // 0 = not deactivated
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

    function setGroupVerifier(uint256 groupId, address verifier) external;

    // ============ View Functions ============

    function groupAddress() external view returns (address);
    function getGroupInfo(
        uint256 groupId
    ) external view returns (GroupInfo memory);
    function getGroupsByOwner(
        address owner
    ) external view returns (uint256[] memory);
    function getAllActivatedGroupIds() external view returns (uint256[] memory);
    function isGroupActive(uint256 groupId) external view returns (bool);
    function canVerify(
        address verifier,
        uint256 groupId
    ) external view returns (bool);

    // --- Config Parameters (immutable) ---
    function minGovVoteRatioBps() external view returns (uint256);
    function capacityMultiplier() external view returns (uint256);
    function stakingMultiplier() external view returns (uint256);
    function maxJoinAmountMultiplier() external view returns (uint256);
    function minJoinAmount() external view returns (uint256);

    // --- Capacity ---
    function calculateJoinMaxAmount() external view returns (uint256);
    function getMaxCapacityForOwner(
        address owner
    ) external view returns (uint256);
    function getTotalStakedByOwner(
        address owner
    ) external view returns (uint256);
    function getExpandableInfo()
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
