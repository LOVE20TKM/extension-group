// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupNotice} from "./interface/IGroupNotice.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract GroupNotice is IGroupNotice {
    uint256 public constant MAX_CONTENT_LENGTH = 8192;

    struct Notice {
        string content;
        uint256 timestamp;
        uint256 blockNumber;
        address publisher;
    }

    IERC721 internal immutable _group;

    // tokenAddress => actionId => groupId => owner => delegate
    mapping(address => mapping(uint256 => mapping(uint256 => mapping(address => address))))
        private _delegates;
    // tokenAddress => actionId => groupId => Notice[]
    mapping(address => mapping(uint256 => mapping(uint256 => Notice[])))
        private _notices;

    constructor(address groupAddress_) {
        if (groupAddress_ == address(0)) revert ZeroAddress();
        _group = IERC721(groupAddress_);
    }

    function GROUP_ADDRESS() external view returns (address) {
        return address(_group);
    }

    function setDelegate(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        address delegate_
    ) external {
        if (delegate_ == msg.sender) revert InvalidDelegate();
        if (_group.ownerOf(groupId) != msg.sender) revert OnlyGroupOwner();
        _delegates[tokenAddress][actionId][groupId][msg.sender] = delegate_;
    }

    function delegate(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external view returns (address) {
        return
            _delegates[tokenAddress][actionId][groupId][
                _group.ownerOf(groupId)
            ];
    }

    function publish(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        string calldata content
    ) external {
        uint256 len = bytes(content).length;
        if (len == 0) revert ContentEmpty();
        if (len > MAX_CONTENT_LENGTH) revert ContentTooLong();

        address owner = _group.ownerOf(groupId);
        address currentDelegate = _delegates[tokenAddress][actionId][groupId][
            owner
        ];
        if (owner != msg.sender && currentDelegate != msg.sender) {
            revert OnlyGroupOwnerOrDelegate();
        }

        // Publisher is always the group owner, not the delegate
        Notice memory n = Notice({
            content: content,
            timestamp: block.timestamp,
            blockNumber: block.number,
            publisher: owner
        });
        uint256 index = _notices[tokenAddress][actionId][groupId].length;
        _notices[tokenAddress][actionId][groupId].push(n);

        emit Publish({
            tokenAddress: tokenAddress,
            actionId: actionId,
            groupId: groupId,
            publisher: owner,
            delegate: currentDelegate,
            index: index,
            blockNumber: n.blockNumber,
            timestamp: n.timestamp,
            content: content
        });
    }

    function noticeCount(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external view returns (uint256) {
        return _notices[tokenAddress][actionId][groupId].length;
    }

    function getNotices(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 offset,
        uint256 limit,
        bool reverse
    )
        external
        view
        returns (
            string[] memory contents,
            uint256[] memory timestamps,
            uint256[] memory blockNumbers,
            address[] memory publishers,
            uint256 totalCount
        )
    {
        if (limit == 0) revert LimitZero();

        Notice[] storage arr = _notices[tokenAddress][actionId][groupId];
        totalCount = arr.length;
        if (offset >= totalCount) revert OffsetOutOfBounds();

        // Calculate start index based on reverse flag
        uint256 startIdx = reverse ? totalCount - 1 - offset : offset;

        uint256 endIdx;
        uint256 count;

        if (reverse) {
            // Reverse: offset 0 = latest, go backwards
            endIdx = startIdx > limit - 1 ? startIdx - limit + 1 : 0;
            count = startIdx - endIdx + 1;
        } else {
            // Forward: offset 0 = earliest, go forwards
            endIdx = offset + limit > totalCount ? totalCount : offset + limit;
            count = endIdx - startIdx;
        }

        contents = new string[](count);
        timestamps = new uint256[](count);
        blockNumbers = new uint256[](count);
        publishers = new address[](count);

        for (uint256 i; i < count; ) {
            Notice storage n = arr[reverse ? startIdx - i : startIdx + i];
            contents[i] = n.content;
            timestamps[i] = n.timestamp;
            blockNumbers[i] = n.blockNumber;
            publishers[i] = n.publisher;
            unchecked {
                ++i;
            }
        }
    }
}
