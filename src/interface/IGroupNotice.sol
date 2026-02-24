// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupNoticeEvents {
    event Publish(
        address indexed tokenAddress,
        uint256 indexed actionId,
        uint256 indexed groupId,
        address publisher,
        uint256 index,
        uint256 blockNumber,
        uint256 timestamp,
        string content
    );
}

interface IGroupNoticeErrors {
    error OnlyGroupOwner();
    error ContentTooLong();
    error ContentEmpty();
    error ZeroAddress();
}

interface IGroupNotice is IGroupNoticeEvents, IGroupNoticeErrors {
    function MAX_CONTENT_LENGTH() external view returns (uint256);
    function GROUP_ADDRESS() external view returns (address);

    function publish(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        string calldata content
    ) external;

    function noticeCount(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external view returns (uint256);

    function getNotices(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 offset,
        uint256 limit
    )
        external
        view
        returns (
            string[] memory contents,
            uint256[] memory timestamps,
            uint256[] memory blockNumbers,
            address[] memory publishers,
            uint256 totalCount
        );
}
