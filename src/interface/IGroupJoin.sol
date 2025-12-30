// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupJoin {
    error InvalidJoinTokenAddress();
    error JoinAmountZero();
    error AlreadyInOtherGroup();
    error NotInGroup();
    error AmountBelowMinimum();
    error AmountExceedsAccountCap();
    error OwnerCapacityExceeded();
    error GroupCapacityExceeded();
    error GroupAccountsFull();
    error CannotJoinDeactivatedGroup();
    error InvalidFactory();
    error AlreadyInitialized();

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
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 amount,
        string[] memory verificationInfos
    ) external;

    function exit(address tokenAddress, uint256 actionId) external;

    function joinInfo(
        address tokenAddress,
        uint256 actionId,
        address account
    )
        external
        view
        returns (uint256 joinedRound, uint256 amount, uint256 groupId);

    function accountsByGroupIdCount(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external view returns (uint256);

    function accountsByGroupIdAtIndex(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 index
    ) external view returns (address);

    function groupIdByAccountByRound(
        address tokenAddress,
        uint256 actionId,
        address account,
        uint256 round
    ) external view returns (uint256);

    function totalJoinedAmountByGroupId(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external view returns (uint256);

    function totalJoinedAmountByGroupIdByRound(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 round
    ) external view returns (uint256);

    function totalJoinedAmount(
        address tokenAddress,
        uint256 actionId
    ) external view returns (uint256);

    function totalJoinedAmountByRound(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view returns (uint256);

    function accountCountByGroupIdByRound(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 round
    ) external view returns (uint256);

    function accountByGroupIdAndIndexByRound(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 index,
        uint256 round
    ) external view returns (address);

    function amountByAccountByRound(
        address tokenAddress,
        uint256 actionId,
        address account,
        uint256 round
    ) external view returns (uint256);
}
