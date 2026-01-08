// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupJoin {
    error InvalidJoinTokenAddress();
    error JoinAmountZero();
    error AlreadyInOtherGroup();
    error NotJoinedAction();
    error AmountBelowMinimum();
    error AmountExceedsAccountCap();
    error OwnerCapacityExceeded();
    error GroupCapacityExceeded();
    error GroupAccountsFull();
    error CannotJoinDeactivatedGroup();
    error NotRegisteredExtensionInFactory();
    error ExtensionNotInitialized();

    event Join(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 indexed groupId,
        address account,
        uint256 amount
    );
    event Exit(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 indexed groupId,
        address account,
        uint256 amount
    );

    function initialize(address factory_) external;

    function FACTORY_ADDRESS() external view returns (address);

    function join(
        address extension,
        uint256 groupId,
        uint256 amount,
        string[] memory verificationInfos
    ) external;

    function exit(address extension) external;

    function joinInfo(
        address extension,
        address account
    )
        external
        view
        returns (uint256 joinedRound, uint256 amount, uint256 groupId);

    function accountsByGroupId(
        address extension,
        uint256 groupId
    ) external view returns (address[] memory);

    function accountsByGroupIdCount(
        address extension,
        uint256 groupId
    ) external view returns (uint256);

    function accountsByGroupIdAtIndex(
        address extension,
        uint256 groupId,
        uint256 index
    ) external view returns (address);

    function groupIdByAccountByRound(
        address extension,
        uint256 round,
        address account
    ) external view returns (uint256);

    function totalJoinedAmountByGroupId(
        address extension,
        uint256 groupId
    ) external view returns (uint256);

    function totalJoinedAmountByGroupIdByRound(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function joinedAmount(address extension) external view returns (uint256);

    function joinedAmountByRound(
        address extension,
        uint256 round
    ) external view returns (uint256);

    function accountsByGroupIdByRound(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view returns (address[] memory);

    function accountsByGroupIdByRoundCount(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function accountsByGroupIdByRoundAtIndex(
        address extension,
        uint256 round,
        uint256 groupId,
        uint256 index
    ) external view returns (address);

    function joinedAmountByAccountByRound(
        address extension,
        uint256 round,
        address account
    ) external view returns (uint256);
}
