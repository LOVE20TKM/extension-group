// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILOVE20Extension} from "@extension/src/interface/ILOVE20Extension.sol";

/// @title ILOVE20ExtensionGroupService
/// @notice Interface for group service provider reward extension
interface ILOVE20ExtensionGroupService is ILOVE20Extension {
    // ============ Errors ============

    error NoActiveGroups();
    error AlreadyJoined();
    error NotJoined();
    error InvalidBasisPoints();
    error TooManyRecipients();
    error ZeroAddress();
    error ZeroBasisPoints();
    error ArrayLengthMismatch();

    // ============ Events ============

    event Join(address indexed account, uint256 joinedValue, uint256 round);
    event Exit(address indexed account, uint256 round);
    event RecipientsUpdated(
        address indexed account,
        uint256 round,
        address[] recipients,
        uint256[] basisPoints
    );

    // ============ Constants ============

    function BASIS_POINTS_BASE() external view returns (uint256);

    // ============ Immutables ============

    function GROUP_ACTION_ADDRESS() external view returns (address);
    function MAX_RECIPIENTS() external view returns (uint256);

    function getRecipientsByRound(
        address account,
        uint256 round
    )
        external
        view
        returns (address[] memory recipients, uint256[] memory basisPoints);

    function rewardByRecipient(
        uint256 round,
        address joiner,
        address recipient
    ) external view returns (uint256);

    // ============ Write Functions ============

    function join() external;

    function setRecipients(
        address[] calldata recipients,
        uint256[] calldata basisPoints
    ) external;
}
