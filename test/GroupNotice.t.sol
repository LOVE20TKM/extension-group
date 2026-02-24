// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";
import {GroupNotice} from "../src/GroupNotice.sol";
import {IGroupNotice, IGroupNoticeErrors, IGroupNoticeEvents} from "../src/interface/IGroupNotice.sol";
import {MockGroup} from "./mocks/MockGroup.sol";

contract GroupNoticeTest is Test, IGroupNoticeEvents {
    GroupNotice public groupNotice;
    MockGroup public group;

    address tokenAddr = address(0x100);
    uint256 constant ACTION_ID = 1;
    uint256 constant GROUP_ID = 1;
    uint256 constant MAX_CONTENT_LENGTH = 4096;

    address owner = address(0x1);
    address nonOwner = address(0x2);

    function setUp() public {
        group = new MockGroup();
        groupNotice = new GroupNotice(address(group));
        group.mint(owner, "TestGroup");
    }

    function test_Constructor_ZeroAddress_Reverts() public {
        vm.expectRevert(IGroupNoticeErrors.ZeroAddress.selector);
        new GroupNotice(address(0));
    }

    function test_Publish_AsOwner_Succeeds() public {
        string memory content = "Hello chain group";
        vm.prank(owner);
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, content);

        assertEq(groupNotice.noticeCount(tokenAddr, ACTION_ID, GROUP_ID), 1);

        (
            string[] memory contents,
            uint256[] memory timestamps,
            uint256[] memory blockNumbers,
            address[] memory publishers,
            uint256 totalCount
        ) = groupNotice.getNotices(tokenAddr, ACTION_ID, GROUP_ID, 0, 10);

        assertEq(totalCount, 1);
        assertEq(contents.length, 1);
        assertEq(contents[0], content);
        assertEq(timestamps[0], block.timestamp);
        assertEq(blockNumbers[0], block.number);
        assertEq(publishers[0], owner);
    }

    function test_Publish_NonOwner_Reverts() public {
        vm.prank(nonOwner);
        vm.expectRevert(IGroupNoticeErrors.OnlyGroupOwner.selector);
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "content");
    }

    function test_Publish_EmptyContent_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(IGroupNoticeErrors.ContentEmpty.selector);
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "");
    }

    function test_Publish_ContentTooLong_Reverts() public {
        bytes memory b = new bytes(MAX_CONTENT_LENGTH + 1);
        for (uint256 i; i < b.length; i++) b[i] = "a";
        string memory longContent = string(b);
        vm.prank(owner);
        vm.expectRevert(IGroupNoticeErrors.ContentTooLong.selector);
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, longContent);
    }

    function test_Publish_ExactlyMaxLength_Succeeds() public {
        bytes memory b = new bytes(MAX_CONTENT_LENGTH);
        for (uint256 i; i < b.length; i++) b[i] = "a";
        string memory maxContent = string(b);
        vm.prank(owner);
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, maxContent);
        assertEq(groupNotice.noticeCount(tokenAddr, ACTION_ID, GROUP_ID), 1);
    }

    function test_GetNotices_EmptyList() public view {
        (
            string[] memory contents,
            uint256[] memory timestamps,
            uint256[] memory blockNumbers,
            address[] memory publishers,
            uint256 totalCount
        ) = groupNotice.getNotices(tokenAddr, ACTION_ID, GROUP_ID, 0, 10);

        assertEq(totalCount, 0);
        assertEq(contents.length, 0);
        assertEq(timestamps.length, 0);
        assertEq(blockNumbers.length, 0);
        assertEq(publishers.length, 0);
    }

    function test_GetNotices_LargeLimit_NoOverflow() public {
        vm.prank(owner);
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "one");

        (string[] memory c, , , , uint256 tc) = groupNotice.getNotices(
            tokenAddr, ACTION_ID, GROUP_ID, 0, type(uint256).max
        );
        assertEq(tc, 1);
        assertEq(c.length, 1);
        assertEq(c[0], "one");
    }

    function test_GetNotices_OffsetBeyondTotal_ReturnsEmpty() public {
        vm.prank(owner);
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "only one");

        (
            string[] memory contents,
            ,
            ,
            ,
            uint256 totalCount
        ) = groupNotice.getNotices(tokenAddr, ACTION_ID, GROUP_ID, 5, 10);

        assertEq(totalCount, 1);
        assertEq(contents.length, 0);
    }

    function test_GetNotices_Pagination_MultiPage() public {
        string[5] memory contents = ["notice0", "notice1", "notice2", "notice3", "notice4"];
        vm.startPrank(owner);
        for (uint256 i; i < 5; i++) {
            groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, contents[i]);
        }
        vm.stopPrank();

        uint256 totalCount = groupNotice.noticeCount(tokenAddr, ACTION_ID, GROUP_ID);
        assertEq(totalCount, 5);

        (string[] memory c0, , , address[] memory p0, uint256 tc0) =
            groupNotice.getNotices(tokenAddr, ACTION_ID, GROUP_ID, 0, 2);
        assertEq(tc0, 5);
        assertEq(c0.length, 2);
        assertEq(c0[0], "notice0");
        assertEq(c0[1], "notice1");
        assertEq(p0[0], owner);
        assertEq(p0[1], owner);

        (string[] memory c1, , , , uint256 tc1) =
            groupNotice.getNotices(tokenAddr, ACTION_ID, GROUP_ID, 2, 2);
        assertEq(tc1, 5);
        assertEq(c1.length, 2);
        assertEq(c1[0], "notice2");
        assertEq(c1[1], "notice3");

        (string[] memory c2, , , , uint256 tc2) =
            groupNotice.getNotices(tokenAddr, ACTION_ID, GROUP_ID, 4, 2);
        assertEq(tc2, 5);
        assertEq(c2.length, 1);
        assertEq(c2[0], "notice4");
    }

    function test_EmitPublish() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit Publish({
            tokenAddress: tokenAddr,
            actionId: ACTION_ID,
            groupId: GROUP_ID,
            publisher: owner,
            index: 0,
            blockNumber: block.number,
            timestamp: block.timestamp,
            content: "test content"
        });
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "test content");
    }

    function test_MaxContentLength() public view {
        assertEq(groupNotice.MAX_CONTENT_LENGTH(), MAX_CONTENT_LENGTH);
    }

    function test_GroupAddress() public view {
        assertEq(groupNotice.GROUP_ADDRESS(), address(group));
    }
}
