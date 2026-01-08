// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupService {
    error NoActiveGroups();
    error InvalidRatio();
    error TooManyRecipients();
    error ZeroAddress();
    error ZeroRatio();
    error ArrayLengthMismatch();
    error DuplicateAddress();
    error InvalidGroupActionTokenAddress();
    error InvalidExtension();
    error NotGroupOwner();
    error RecipientCannotBeSelf();

    event UpdateRecipients(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 indexed groupId,
        address account,
        address[] recipients,
        uint256[] ratios
    );

    function PRECISION() external view returns (uint256);
    function DEFAULT_MAX_RECIPIENTS() external view returns (uint256);

    function GROUP_ACTION_TOKEN_ADDRESS() external view returns (address);
    function GROUP_ACTION_FACTORY_ADDRESS() external view returns (address);

    function actionIdsWithRecipients(
        address account,
        uint256 round
    ) external view returns (uint256[] memory);

    function groupIdsByActionIdWithRecipients(
        address account,
        uint256 actionId,
        uint256 round
    ) external view returns (uint256[] memory);

    function recipients(
        address groupOwner,
        uint256 actionId,
        uint256 groupId,
        uint256 round
    ) external view returns (address[] memory addrs, uint256[] memory ratios);

    function recipientsLatest(
        address groupOwner,
        uint256 actionId,
        uint256 groupId
    ) external view returns (address[] memory addrs, uint256[] memory ratios);

    function rewardByRecipient(
        uint256 round,
        address groupOwner,
        uint256 actionId,
        uint256 groupId,
        address recipient
    ) external view returns (uint256);

    function rewardDistribution(
        uint256 round,
        address groupOwner,
        uint256 actionId,
        uint256 groupId
    )
        external
        view
        returns (
            address[] memory addrs,
            uint256[] memory ratios,
            uint256[] memory amounts,
            uint256 ownerAmount
        );

    function hasActiveGroups(address account) external view returns (bool);

    function generatedActionRewardByVerifier(
        uint256 round,
        address verifier
    ) external view returns (uint256 amount);

    function generatedActionReward(
        uint256 round
    ) external view returns (uint256);

    function setRecipients(
        uint256 actionId,
        uint256 groupId,
        address[] calldata addrs,
        uint256[] calldata ratios
    ) external;
}
