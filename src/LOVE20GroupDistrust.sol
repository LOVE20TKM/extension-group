// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILOVE20GroupDistrust} from "./interface/ILOVE20GroupDistrust.sol";
import {ILOVE20Verify} from "@core/interfaces/ILOVE20Verify.sol";
import {
    ILOVE20ExtensionCenter
} from "@extension/src/interface/ILOVE20ExtensionCenter.sol";
import {ILOVE20Group} from "@group/interfaces/ILOVE20Group.sol";

/// @title LOVE20GroupDistrust
/// @notice Singleton contract for managing distrust votes across all GroupAction extensions
/// @dev Only registered GroupAction extensions can call distrustVote
contract LOVE20GroupDistrust is ILOVE20GroupDistrust {
    // ============ Immutables ============

    ILOVE20ExtensionCenter internal immutable _center;
    ILOVE20Verify internal immutable _verify;
    ILOVE20Group internal immutable _group;

    // ============ State ============

    /// @dev extension => round => groupOwner => total distrust votes
    mapping(address => mapping(uint256 => mapping(address => uint256)))
        internal _distrustVotesByGroupOwner;

    /// @dev extension => round => voter => groupOwner => distrust votes
    mapping(address => mapping(uint256 => mapping(address => mapping(address => uint256))))
        internal _distrustVotesByVoterByGroupOwner;

    /// @dev extension => round => voter => groupOwner => reason
    mapping(address => mapping(uint256 => mapping(address => mapping(address => string))))
        internal _distrustReason;

    // ============ Constructor ============

    constructor(
        address centerAddress_,
        address verifyAddress_,
        address groupAddress_
    ) {
        _center = ILOVE20ExtensionCenter(centerAddress_);
        _verify = ILOVE20Verify(verifyAddress_);
        _group = ILOVE20Group(groupAddress_);
    }

    // ============ Write Functions ============

    /// @inheritdoc ILOVE20GroupDistrust
    function distrustVote(
        address tokenAddress,
        uint256 actionId,
        address groupOwner,
        uint256 amount,
        string calldata reason,
        address voter
    ) external override {
        // Verify msg.sender is a registered extension for this token/actionId
        address registeredExtension = _center.extension(tokenAddress, actionId);
        if (registeredExtension != msg.sender) revert NotRegisteredExtension();

        uint256 currentRound = _verify.currentRound();

        // Check voter has voted for GroupAction (msg.sender)
        uint256 verifyVotes = _verify.scoreByVerifierByActionIdByAccount(
            tokenAddress,
            currentRound,
            voter,
            actionId,
            msg.sender
        );
        if (verifyVotes == 0) revert NotGovernor();

        // Check accumulated votes don't exceed verify votes
        uint256 currentVotes = _distrustVotesByVoterByGroupOwner[msg.sender][
            currentRound
        ][voter][groupOwner];
        if (currentVotes + amount > verifyVotes)
            revert DistrustVoteExceedsLimit();

        if (bytes(reason).length == 0) revert InvalidReason();

        // Record vote
        _distrustVotesByVoterByGroupOwner[msg.sender][currentRound][voter][
            groupOwner
        ] += amount;
        _distrustVotesByGroupOwner[msg.sender][currentRound][
            groupOwner
        ] += amount;
        _distrustReason[msg.sender][currentRound][voter][groupOwner] = reason;

        emit DistrustVote(
            tokenAddress,
            currentRound,
            actionId,
            groupOwner,
            voter,
            amount,
            reason
        );
    }

    // ============ View Functions ============

    /// @inheritdoc ILOVE20GroupDistrust
    function totalVerifyVotes(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view override returns (uint256) {
        address extension = _center.extension(tokenAddress, actionId);
        return
            _verify.scoreByActionIdByAccount(
                tokenAddress,
                round,
                actionId,
                extension
            );
    }

    /// @inheritdoc ILOVE20GroupDistrust
    function distrustVotesByGroupOwner(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address groupOwner
    ) external view override returns (uint256) {
        address extension = _center.extension(tokenAddress, actionId);
        return _distrustVotesByGroupOwner[extension][round][groupOwner];
    }

    /// @inheritdoc ILOVE20GroupDistrust
    function distrustVotesByGroupId(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        address groupOwner = _group.ownerOf(groupId);
        address extension = _center.extension(tokenAddress, actionId);
        return _distrustVotesByGroupOwner[extension][round][groupOwner];
    }

    /// @inheritdoc ILOVE20GroupDistrust
    function distrustVotesByVoterByGroupOwner(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address voter,
        address groupOwner
    ) external view override returns (uint256) {
        address extension = _center.extension(tokenAddress, actionId);
        return
            _distrustVotesByVoterByGroupOwner[extension][round][voter][
                groupOwner
            ];
    }

    /// @inheritdoc ILOVE20GroupDistrust
    function distrustReason(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address voter,
        address groupOwner
    ) external view override returns (string memory) {
        address extension = _center.extension(tokenAddress, actionId);
        return _distrustReason[extension][round][voter][groupOwner];
    }
}
