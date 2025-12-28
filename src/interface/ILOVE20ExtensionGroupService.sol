// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    ILOVE20ExtensionJoin
} from "@extension/src/interface/ILOVE20ExtensionJoin.sol";

/// @title ILOVE20ExtensionGroupService
/// @notice Interface for group service provider reward extension
interface ILOVE20ExtensionGroupService is ILOVE20ExtensionJoin {
    // ============ Errors ============

    error NoActiveGroups();
    error InvalidBasisPoints();
    error TooManyRecipients();
    error ZeroAddress();
    error ZeroBasisPoints();
    error ArrayLengthMismatch();
    error DuplicateAddress();
    error InvalidGroupActionTokenAddress();
    error NotGroupOwner();
    error RecipientCannotBeSelf();

    // ============ Events ============

    event RecipientsUpdate(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 indexed groupId,
        address account,
        address[] recipients,
        uint256[] basisPoints
    );

    // ============ Structs ============

    struct GroupDistribution {
        uint256 actionId;
        uint256 groupId;
        uint256 groupReward;
        address[] recipients;
        uint256[] basisPoints;
        uint256[] amounts;
        uint256 ownerAmount;
    }

    // ============ Constants ============

    function BASIS_POINTS_BASE() external view returns (uint256);
    function DEFAULT_MAX_RECIPIENTS() external view returns (uint256);

    // ============ Immutables ============

    function GROUP_ACTION_TOKEN_ADDRESS() external view returns (address);
    function GROUP_ACTION_FACTORY_ADDRESS() external view returns (address);

    // ============ View Functions ============

    function votedGroupActions(
        uint256 round
    )
        external
        view
        returns (uint256[] memory actionIds, address[] memory extensions);

    function actionIdsWithRecipients(
        address account,
        uint256 round
    ) external view returns (uint256[] memory);

    function groupIdsWithRecipients(
        address account,
        uint256 actionId,
        uint256 round
    ) external view returns (uint256[] memory);

    function recipients(
        address groupOwner,
        uint256 actionId,
        uint256 groupId,
        uint256 round
    )
        external
        view
        returns (address[] memory addrs, uint256[] memory basisPoints);

    function recipientsLatest(
        address groupOwner,
        uint256 actionId,
        uint256 groupId
    )
        external
        view
        returns (address[] memory addrs, uint256[] memory basisPoints);

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
            uint256[] memory basisPoints,
            uint256[] memory amounts,
            uint256 ownerAmount
        );

    function rewardDistributionAll(
        uint256 round,
        address groupOwner
    ) external view returns (GroupDistribution[] memory distributions);

    function hasActiveGroups(address account) external view returns (bool);

    function generatedRewardByVerifier(
        uint256 round,
        address verifier
    ) external view returns (uint256 accountReward, uint256 totalReward);

    // ============ Write Functions ============

    function setRecipients(
        uint256 actionId,
        uint256 groupId,
        address[] calldata addrs,
        uint256[] calldata basisPoints
    ) external;
}
