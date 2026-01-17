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
    error CannotJoinInactiveGroup();
    error NotRegisteredExtensionInFactory();
    error ExtensionNotInitialized();
    error InvalidGroupId();
    error AlreadyJoined();
    error TrialAlreadyJoined();
    error TrialArrayLengthMismatch();
    error TrialAccountNotInWaitingList();
    error TrialAccountIsProvider();
    error TrialAccountZero();
    error TrialAmountZero();
    error TrialAccountAlreadyAdded();
    error TrialProviderMismatch();

    event Join(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 indexed groupId,
        address account,
        address provider,
        uint256 amount
    );
    event Exit(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 indexed groupId,
        address account,
        address provider,
        uint256 amount
    );
    event TrialWaitingListUpdated(
        address indexed tokenAddress,
        uint256 actionId,
        uint256 indexed groupId,
        address indexed provider,
        address account,
        uint256 trialAmount,
        bool enabled
    );

    function initialize(address factory_) external;

    function FACTORY_ADDRESS() external view returns (address);

    function join(
        address extension,
        uint256 groupId,
        uint256 amount,
        string[] memory verificationInfos
    ) external;

    function trialJoin(
        address extension,
        uint256 groupId,
        address provider,
        string[] memory verificationInfos
    ) external;

    function exit(address extension) external;

    function trialExit(address extension, address account) external;

    function joinInfo(
        address extension,
        address account
    )
        external
        view
        returns (
            uint256 joinedRound,
            uint256 amount,
            uint256 groupId,
            address provider
        );

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

    function totalJoinedAmountByGroupOwner(
        address extension,
        address owner
    ) external view returns (uint256);

    function isAccountInRangeByRound(
        address extension,
        uint256 round,
        uint256 groupId,
        address account,
        uint256 startIndex,
        uint256 endIndex
    ) external view returns (bool);

    function trialWaitingListAdd(
        address extension,
        uint256 groupId,
        address[] memory trialAccounts,
        uint256[] memory trialAmounts
    ) external;

    function trialWaitingListRemove(
        address extension,
        uint256 groupId,
        address[] memory trialAccounts
    ) external;

    function trialWaitingListRemoveAll(
        address extension,
        uint256 groupId
    ) external;

    function trialWaitingListByProvider(
        address extension,
        uint256 groupId,
        address provider
    ) external view returns (address[] memory, uint256[] memory);

    function trialWaitingListByProviderCount(
        address extension,
        uint256 groupId,
        address provider
    ) external view returns (uint256);

    function trialWaitingListByProviderAtIndex(
        address extension,
        uint256 groupId,
        address provider,
        uint256 index
    ) external view returns (address, uint256);

    function trialJoinedListByProvider(
        address extension,
        uint256 groupId,
        address provider
    ) external view returns (address[] memory, uint256[] memory);

    function trialJoinedListByProviderCount(
        address extension,
        uint256 groupId,
        address provider
    ) external view returns (uint256);

    function trialJoinedListByProviderAtIndex(
        address extension,
        uint256 groupId,
        address provider,
        uint256 index
    ) external view returns (address, uint256);

    // ------ global view functions (no extension parameter) ------

    // gGroupIds functions
    function gGroupIds() external view returns (uint256[] memory);
    function gGroupIdsCount() external view returns (uint256);
    function gGroupIdsAtIndex(uint256 index) external view returns (uint256);

    // gGroupIdsByAccount functions
    function gGroupIdsByAccount(
        address account
    ) external view returns (uint256[] memory);

    function gGroupIdsByAccountCount(
        address account
    ) external view returns (uint256);

    function gGroupIdsByAccountAtIndex(
        address account,
        uint256 index
    ) external view returns (uint256);

    // gGroupIdsByTokenAddress functions
    function gGroupIdsByTokenAddress(
        address tokenAddress
    ) external view returns (uint256[] memory);

    function gGroupIdsByTokenAddressCount(
        address tokenAddress
    ) external view returns (uint256);

    function gGroupIdsByTokenAddressAtIndex(
        address tokenAddress,
        uint256 index
    ) external view returns (uint256);

    // gGroupIdsByTokenAddressByAccount functions
    function gGroupIdsByTokenAddressByAccount(
        address tokenAddress,
        address account
    ) external view returns (uint256[] memory);

    function gGroupIdsByTokenAddressByAccountCount(
        address tokenAddress,
        address account
    ) external view returns (uint256);

    function gGroupIdsByTokenAddressByAccountAtIndex(
        address tokenAddress,
        address account,
        uint256 index
    ) external view returns (uint256);

    function gGroupIdsByTokenAddressByActionId(
        address tokenAddress,
        uint256 actionId
    ) external view returns (uint256[] memory);

    function gGroupIdsByTokenAddressByActionIdCount(
        address tokenAddress,
        uint256 actionId
    ) external view returns (uint256);

    function gGroupIdsByTokenAddressByActionIdAtIndex(
        address tokenAddress,
        uint256 actionId,
        uint256 index
    ) external view returns (uint256);

    // gTokenAddresses functions
    function gTokenAddresses() external view returns (address[] memory);

    function gTokenAddressesCount() external view returns (uint256);

    function gTokenAddressesAtIndex(
        uint256 index
    ) external view returns (address);

    // gTokenAddressesByAccount functions
    function gTokenAddressesByAccount(
        address account
    ) external view returns (address[] memory);

    function gTokenAddressesByAccountCount(
        address account
    ) external view returns (uint256);

    function gTokenAddressesByAccountAtIndex(
        address account,
        uint256 index
    ) external view returns (address);

    // gTokenAddressesByGroupId functions
    function gTokenAddressesByGroupId(
        uint256 groupId
    ) external view returns (address[] memory);

    function gTokenAddressesByGroupIdCount(
        uint256 groupId
    ) external view returns (uint256);

    function gTokenAddressesByGroupIdAtIndex(
        uint256 groupId,
        uint256 index
    ) external view returns (address);

    // gTokenAddressesByGroupIdByAccount functions
    function gTokenAddressesByGroupIdByAccount(
        uint256 groupId,
        address account
    ) external view returns (address[] memory);

    function gTokenAddressesByGroupIdByAccountCount(
        uint256 groupId,
        address account
    ) external view returns (uint256);

    function gTokenAddressesByGroupIdByAccountAtIndex(
        uint256 groupId,
        address account,
        uint256 index
    ) external view returns (address);

    // gActionIdsByTokenAddress functions
    function gActionIdsByTokenAddress(
        address tokenAddress
    ) external view returns (uint256[] memory);

    function gActionIdsByTokenAddressCount(
        address tokenAddress
    ) external view returns (uint256);

    function gActionIdsByTokenAddressAtIndex(
        address tokenAddress,
        uint256 index
    ) external view returns (uint256);

    // gActionIdsByTokenAddressByAccount functions
    function gActionIdsByTokenAddressByAccount(
        address tokenAddress,
        address account
    ) external view returns (uint256[] memory);

    function gActionIdsByTokenAddressByAccountCount(
        address tokenAddress,
        address account
    ) external view returns (uint256);

    function gActionIdsByTokenAddressByAccountAtIndex(
        address tokenAddress,
        address account,
        uint256 index
    ) external view returns (uint256);

    // gActionIdsByTokenAddressByGroupId functions
    function gActionIdsByTokenAddressByGroupId(
        address tokenAddress,
        uint256 groupId
    ) external view returns (uint256[] memory);

    function gActionIdsByTokenAddressByGroupIdCount(
        address tokenAddress,
        uint256 groupId
    ) external view returns (uint256);

    function gActionIdsByTokenAddressByGroupIdAtIndex(
        address tokenAddress,
        uint256 groupId,
        uint256 index
    ) external view returns (uint256);

    // gActionIdsByTokenAddressByGroupIdByAccount functions
    function gActionIdsByTokenAddressByGroupIdByAccount(
        address tokenAddress,
        uint256 groupId,
        address account
    ) external view returns (uint256[] memory);

    function gActionIdsByTokenAddressByGroupIdByAccountCount(
        address tokenAddress,
        uint256 groupId,
        address account
    ) external view returns (uint256);

    function gActionIdsByTokenAddressByGroupIdByAccountAtIndex(
        address tokenAddress,
        uint256 groupId,
        address account,
        uint256 index
    ) external view returns (uint256);

    // gAccounts functions
    function gAccounts() external view returns (address[] memory);

    function gAccountsCount() external view returns (uint256);

    function gAccountsAtIndex(uint256 index) external view returns (address);

    // gAccountsByGroupId functions
    function gAccountsByGroupId(
        uint256 groupId
    ) external view returns (address[] memory);

    function gAccountsByGroupIdCount(
        uint256 groupId
    ) external view returns (uint256);

    function gAccountsByGroupIdAtIndex(
        uint256 groupId,
        uint256 index
    ) external view returns (address);

    // gAccountsByTokenAddress functions
    function gAccountsByTokenAddress(
        address tokenAddress
    ) external view returns (address[] memory);

    function gAccountsByTokenAddressCount(
        address tokenAddress
    ) external view returns (uint256);

    function gAccountsByTokenAddressAtIndex(
        address tokenAddress,
        uint256 index
    ) external view returns (address);

    // gAccountsByTokenAddressByGroupId functions
    function gAccountsByTokenAddressByGroupId(
        address tokenAddress,
        uint256 groupId
    ) external view returns (address[] memory);

    function gAccountsByTokenAddressByGroupIdCount(
        address tokenAddress,
        uint256 groupId
    ) external view returns (uint256);

    function gAccountsByTokenAddressByGroupIdAtIndex(
        address tokenAddress,
        uint256 groupId,
        uint256 index
    ) external view returns (address);
}
