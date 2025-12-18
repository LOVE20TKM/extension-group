// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface ILOVE20GroupManager {
    // ============ Errors ============

    error ConfigAlreadySet();
    error ConfigNotSet();
    error NotRegisteredExtension();
    error GroupNotFound();
    error GroupAlreadyActivated();
    error GroupAlreadyDeactivated();
    error GroupNotActive();
    error InvalidMinMaxJoinAmount();
    error InvalidMaxAccounts();
    error CannotDeactivateInActivatedRound();
    error OnlyGroupOwner();

    // ============ Events ============

    event ConfigSet(address indexed extension, address stakeTokenAddress);

    event GroupActivate(
        address indexed tokenAddress,
        uint256 indexed actionId,
        uint256 round,
        uint256 groupId,
        address owner,
        uint256 maxCapacity,
        uint256 maxAccounts
    );
    event GroupDeactivate(
        address indexed tokenAddress,
        uint256 indexed actionId,
        uint256 round,
        uint256 groupId,
        uint256 returnedStake
    );
    event GroupInfoUpdate(
        address indexed tokenAddress,
        uint256 indexed actionId,
        uint256 round,
        uint256 groupId,
        string newDescription,
        uint256 newMaxCapacity,
        uint256 newMinJoinAmount,
        uint256 newMaxJoinAmount,
        uint256 newMaxAccounts
    );

    // ============ Structs ============

    struct Config {
        address stakeTokenAddress;
        uint256 activationStakeAmount;
        uint256 maxJoinAmountMultiplier;
        uint256 verifyCapacityMultiplier;
    }

    struct GroupInfo {
        uint256 groupId;
        string description;
        uint256 maxCapacity; // 0 = use owner's theoretical max capacity
        uint256 minJoinAmount;
        uint256 maxJoinAmount; // 0 = no limit
        uint256 maxAccounts; // 0 = no limit
        bool isActive;
        uint256 activatedRound; // 0 = never activated
        uint256 deactivatedRound; // 0 = never deactivated
    }

    // ============ Config Functions ============

    /// @notice Returns the ExtensionCenter contract address
    function CENTER_ADDRESS() external view returns (address);

    /// @notice Returns the Group NFT contract address (set at construction)
    function GROUP_ADDRESS() external view returns (address);

    /// @notice Returns the Stake contract address (set at construction)
    function STAKE_ADDRESS() external view returns (address);

    /// @notice Returns the Join contract address (set at construction)
    function JOIN_ADDRESS() external view returns (address);

    /// @notice Set config for extension (msg.sender is the extension)
    function setConfig(
        address stakeTokenAddress,
        uint256 activationStakeAmount,
        uint256 maxJoinAmountMultiplier,
        uint256 verifyCapacityMultiplier
    ) external;

    function config(
        address tokenAddress,
        uint256 actionId
    )
        external
        view
        returns (
            address stakeTokenAddress,
            uint256 activationStakeAmount,
            uint256 maxJoinAmountMultiplier,
            uint256 verifyCapacityMultiplier
        );

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
    ) external returns (bool);

    function deactivateGroup(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external;

    function updateGroupInfo(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        string memory newDescription,
        uint256 newMaxCapacity,
        uint256 newMinJoinAmount,
        uint256 newMaxJoinAmount,
        uint256 newMaxAccounts
    ) external;

    // ============ View Functions ============

    function groupInfo(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    )
        external
        view
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
        );

    function activeGroupIdsByOwner(
        address tokenAddress,
        uint256 actionId,
        address owner
    ) external view returns (uint256[] memory);

    function activeGroupIds(
        address tokenAddress,
        uint256 actionId
    ) external view returns (uint256[] memory);

    function activeGroupIdsCount(
        address tokenAddress,
        uint256 actionId
    ) external view returns (uint256);

    function activeGroupIdsAtIndex(
        address tokenAddress,
        uint256 actionId,
        uint256 index
    ) external view returns (uint256 groupId);

    function isGroupActive(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external view returns (bool);

    // ============ Capacity View Functions ============

    function calculateJoinMaxAmount(
        address tokenAddress,
        uint256 actionId
    ) external view returns (uint256);

    function maxVerifyCapacityByOwner(
        address tokenAddress,
        uint256 actionId,
        address owner
    ) external view returns (uint256);

    function totalStakedByOwner(
        address tokenAddress,
        uint256 actionId,
        address owner
    ) external view returns (uint256);

    function totalStaked(
        address tokenAddress,
        uint256 actionId
    ) external view returns (uint256);
}
