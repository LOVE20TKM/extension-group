// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupManager {
    // ============ Errors ============

    error NotRegisteredExtension();
    error GroupNotFound();
    error GroupAlreadyActivated();
    error GroupAlreadyDeactivated();
    error GroupNotActive();
    error InvalidMinMaxJoinAmount();
    error InvalidMaxAccounts();
    error CannotDeactivateInActivatedRound();
    error OnlyGroupOwner();
    error ExtensionTokenActionMismatch();
    error NotRegisteredExtensionInFactory();
    error AlreadyInitialized();
    error InvalidFactory();

    // ============ Events ============

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

    // Config is now stored in ExtensionGroupAction

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

    struct TokenActionPair {
        address tokenAddress;
        uint256 actionId;
    }

    function FACTORY_ADDRESS() external view returns (address);

    /// @notice Returns the precision constant (1e18) used for ratio and factor calculations
    function PRECISION() external view returns (uint256);

    // ============ Initialization ============

    /// @notice Initialize the contract with factory address
    /// @param factory_ The factory address
    function initialize(address factory_) external;

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
    ) external;

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

    function totalStakedByActionIdByOwner(
        address tokenAddress,
        uint256 actionId,
        address owner
    ) external view returns (uint256);

    function totalStaked(
        address tokenAddress,
        uint256 actionId
    ) external view returns (uint256);

    // ============ Extension Activation View Functions ============

    function actionIdsByGroupId(
        address actionFactory,
        address tokenAddress,
        uint256 groupId
    ) external view returns (uint256[] memory);

    function actionIdsByGroupIdCount(
        address actionFactory,
        address tokenAddress,
        uint256 groupId
    ) external view returns (uint256);

    function actionIdsByGroupIdAtIndex(
        address actionFactory,
        address tokenAddress,
        uint256 groupId,
        uint256 index
    ) external view returns (uint256);

    function actionIds(
        address actionFactory,
        address tokenAddress
    ) external view returns (uint256[] memory);

    function actionIdsCount(
        address actionFactory,
        address tokenAddress
    ) external view returns (uint256);

    function actionIdsAtIndex(
        address actionFactory,
        address tokenAddress,
        uint256 index
    ) external view returns (uint256);

    function votedGroupActions(
        address actionFactory,
        address tokenAddress,
        uint256 round
    )
        external
        view
        returns (uint256[] memory actionIds_, address[] memory extensions);

    /// @notice Check if account has any active groups with actions
    /// @param actionFactory The action factory address
    /// @param tokenAddress The token address
    /// @param account The account to check
    /// @return True if account has at least one group with actions
    function hasActiveGroups(
        address actionFactory,
        address tokenAddress,
        address account
    ) external view returns (bool);
}
