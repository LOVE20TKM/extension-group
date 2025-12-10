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

    // ============ Events ============

    event RecipientsUpdate(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        address indexed account,
        address[] recipients,
        uint256[] basisPoints
    );

    // ============ Constants ============

    function BASIS_POINTS_BASE() external view returns (uint256);

    // ============ Immutables ============

    function GROUP_ACTION_ADDRESS() external view returns (address);
    function MAX_RECIPIENTS() external view returns (uint256);

    function recipients(
        address groupOwner,
        uint256 round
    )
        external
        view
        returns (address[] memory addrs, uint256[] memory basisPoints);

    function recipientsLatest(
        address groupOwner
    )
        external
        view
        returns (address[] memory addrs, uint256[] memory basisPoints);

    function rewardByRecipient(
        uint256 round,
        address groupOwner,
        address recipient
    ) external view returns (uint256);

    function rewardDistribution(
        uint256 round,
        address groupOwner
    )
        external
        view
        returns (
            address[] memory addrs,
            uint256[] memory basisPoints,
            uint256[] memory amounts,
            uint256 ownerAmount
        );

    // ============ Write Functions ============

    function setRecipients(
        address[] calldata addrs,
        uint256[] calldata basisPoints
    ) external;
}
