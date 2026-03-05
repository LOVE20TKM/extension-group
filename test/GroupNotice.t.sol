// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";
import {GroupNotice} from "../src/GroupNotice.sol";
import {
    IGroupNotice,
    IGroupNoticeErrors,
    IGroupNoticeEvents
} from "../src/interface/IGroupNotice.sol";
import {MockGroup} from "./mocks/MockGroup.sol";

contract GroupNoticeTest is Test, IGroupNoticeEvents {
    GroupNotice public groupNotice;
    MockGroup public group;

    address tokenAddr = address(0x100);
    uint256 constant ACTION_ID = 1;
    uint256 constant GROUP_ID = 1;
    uint256 constant MAX_CONTENT_LENGTH = 8192;

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
        ) = groupNotice.getNotices(
                tokenAddr,
                ACTION_ID,
                GROUP_ID,
                0,
                10,
                false
            );

        assertEq(totalCount, 1);
        assertEq(contents.length, 1);
        assertEq(contents[0], content);
        assertEq(timestamps[0], block.timestamp);
        assertEq(blockNumbers[0], block.number);
        assertEq(publishers[0], owner);
    }

    function test_Publish_NonOwner_Reverts() public {
        vm.prank(nonOwner);
        vm.expectRevert(IGroupNoticeErrors.OnlyGroupOwnerOrDelegate.selector);
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

    function test_GetNotices_EmptyList() public {
        vm.expectRevert(IGroupNoticeErrors.OffsetOutOfBounds.selector);
        groupNotice.getNotices(tokenAddr, ACTION_ID, GROUP_ID, 0, 10, false);
    }

    function test_GetNotices_LargeLimit_NoOverflow() public {
        vm.prank(owner);
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "one");

        (string[] memory c, , , , uint256 tc) = groupNotice.getNotices(
            tokenAddr,
            ACTION_ID,
            GROUP_ID,
            0,
            type(uint256).max,
            false
        );
        assertEq(tc, 1);
        assertEq(c.length, 1);
        assertEq(c[0], "one");
    }

    function test_GetNotices_OffsetBeyondTotal_ReturnsEmpty() public {
        vm.prank(owner);
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "only one");

        vm.expectRevert(IGroupNoticeErrors.OffsetOutOfBounds.selector);
        groupNotice.getNotices(tokenAddr, ACTION_ID, GROUP_ID, 5, 10, false);
    }

    function test_GetNotices_Pagination_MultiPage() public {
        string[5] memory contents = [
            "notice0",
            "notice1",
            "notice2",
            "notice3",
            "notice4"
        ];
        vm.startPrank(owner);
        for (uint256 i; i < 5; i++) {
            groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, contents[i]);
        }
        vm.stopPrank();

        uint256 totalCount = groupNotice.noticeCount(
            tokenAddr,
            ACTION_ID,
            GROUP_ID
        );
        assertEq(totalCount, 5);

        (string[] memory c0, , , address[] memory p0, uint256 tc0) = groupNotice
            .getNotices(tokenAddr, ACTION_ID, GROUP_ID, 0, 2, false);
        assertEq(tc0, 5);
        assertEq(c0.length, 2);
        assertEq(c0[0], "notice0");
        assertEq(c0[1], "notice1");
        assertEq(p0[0], owner);
        assertEq(p0[1], owner);

        (string[] memory c1, , , , uint256 tc1) = groupNotice.getNotices(
            tokenAddr,
            ACTION_ID,
            GROUP_ID,
            2,
            2,
            false
        );
        assertEq(tc1, 5);
        assertEq(c1.length, 2);
        assertEq(c1[0], "notice2");
        assertEq(c1[1], "notice3");

        (string[] memory c2, , , , uint256 tc2) = groupNotice.getNotices(
            tokenAddr,
            ACTION_ID,
            GROUP_ID,
            4,
            2,
            false
        );
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
            delegate: address(0),
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

    // Delegate tests
    function test_SetDelegate_ByOwner_Succeeds() public {
        address delegateAddr = address(0x3);
        vm.prank(owner);
        groupNotice.setDelegate(tokenAddr, ACTION_ID, GROUP_ID, delegateAddr);

        assertEq(
            groupNotice.delegate(tokenAddr, ACTION_ID, GROUP_ID),
            delegateAddr
        );
    }

    function test_SetDelegate_ByNonOwner_Reverts() public {
        address delegateAddr = address(0x3);
        vm.prank(nonOwner);
        vm.expectRevert(IGroupNoticeErrors.OnlyGroupOwner.selector);
        groupNotice.setDelegate(tokenAddr, ACTION_ID, GROUP_ID, delegateAddr);
    }

    function test_SetDelegate_ToSelf_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(IGroupNoticeErrors.InvalidDelegate.selector);
        groupNotice.setDelegate(tokenAddr, ACTION_ID, GROUP_ID, owner);
    }

    function test_SetDelegate_DifferentTokenActionGroup_Succeeds() public {
        address delegateAddr = address(0x3);
        address tokenAddr2 = address(0x200);
        uint256 actionId2 = 2;
        uint256 groupId2 = 2;

        group.mint(owner, "TestGroup2");

        vm.prank(owner);
        groupNotice.setDelegate(tokenAddr, ACTION_ID, GROUP_ID, delegateAddr);

        // Different tokenAddress, actionId, groupId should have no delegate
        assertEq(
            groupNotice.delegate(tokenAddr2, actionId2, groupId2),
            address(0)
        );

        // Set delegate for another group
        vm.prank(owner);
        groupNotice.setDelegate(tokenAddr2, actionId2, groupId2, delegateAddr);
        assertEq(
            groupNotice.delegate(tokenAddr2, actionId2, groupId2),
            delegateAddr
        );
    }

    function test_Delegate_NotSet_ReturnsZeroAddress() public view {
        assertEq(
            groupNotice.delegate(tokenAddr, ACTION_ID, GROUP_ID),
            address(0)
        );
    }

    function test_Publish_AsDelegate_Succeeds() public {
        address delegateAddr = address(0x3);

        vm.prank(owner);
        groupNotice.setDelegate(tokenAddr, ACTION_ID, GROUP_ID, delegateAddr);

        vm.prank(delegateAddr);
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "delegate content");

        assertEq(groupNotice.noticeCount(tokenAddr, ACTION_ID, GROUP_ID), 1);

        // Verify publisher is owner, not delegate
        (, , , address[] memory publishers, ) = groupNotice.getNotices(
            tokenAddr,
            ACTION_ID,
            GROUP_ID,
            0,
            10,
            false
        );
        assertEq(publishers[0], owner);
    }

    function test_Publish_AsDelegate_DifferentTokenActionGroup_Reverts()
        public
    {
        address delegateAddr = address(0x3);
        address tokenAddr2 = address(0x200);

        vm.prank(owner);
        groupNotice.setDelegate(tokenAddr, ACTION_ID, GROUP_ID, delegateAddr);

        // Try to publish with different tokenAddress
        vm.prank(delegateAddr);
        vm.expectRevert(IGroupNoticeErrors.OnlyGroupOwnerOrDelegate.selector);
        groupNotice.publish(tokenAddr2, ACTION_ID, GROUP_ID, "content");

        // Try to publish with different actionId
        vm.prank(delegateAddr);
        vm.expectRevert(IGroupNoticeErrors.OnlyGroupOwnerOrDelegate.selector);
        groupNotice.publish(tokenAddr, 2, GROUP_ID, "content");

        // Try to publish with different groupId
        vm.prank(delegateAddr);
        vm.expectRevert(IGroupNoticeErrors.OnlyGroupOwnerOrDelegate.selector);
        groupNotice.publish(tokenAddr, ACTION_ID, 2, "content");
    }

    function test_Publish_DelegateAfterOwnerChange_Reverts() public {
        address delegateAddr = address(0x3);
        address newOwner = address(0x4);

        // Owner sets delegate
        vm.prank(owner);
        groupNotice.setDelegate(tokenAddr, ACTION_ID, GROUP_ID, delegateAddr);

        // Transfer ownership
        group.transferFrom(owner, newOwner, GROUP_ID);

        // Original delegate should no longer be able to publish
        vm.prank(delegateAddr);
        vm.expectRevert(IGroupNoticeErrors.OnlyGroupOwnerOrDelegate.selector);
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "content");

        // New owner can publish
        vm.prank(newOwner);
        groupNotice.publish(
            tokenAddr,
            ACTION_ID,
            GROUP_ID,
            "new owner content"
        );
        assertEq(groupNotice.noticeCount(tokenAddr, ACTION_ID, GROUP_ID), 1);
    }

    function test_Delegate_ChangesAfterOwnerTransfer() public {
        address delegateAddr = address(0x3);
        address newOwner = address(0x4);

        // Owner sets delegate
        vm.prank(owner);
        groupNotice.setDelegate(tokenAddr, ACTION_ID, GROUP_ID, delegateAddr);
        assertEq(
            groupNotice.delegate(tokenAddr, ACTION_ID, GROUP_ID),
            delegateAddr
        );

        // Transfer ownership
        group.transferFrom(owner, newOwner, GROUP_ID);

        // Delegate should return address(0) for new owner
        assertEq(
            groupNotice.delegate(tokenAddr, ACTION_ID, GROUP_ID),
            address(0)
        );
    }

    function test_Publish_EventIncludesDelegate() public {
        address delegateAddr = address(0x3);

        vm.prank(owner);
        groupNotice.setDelegate(tokenAddr, ACTION_ID, GROUP_ID, delegateAddr);

        vm.prank(delegateAddr);
        vm.expectEmit(true, true, true, true);
        emit Publish({
            tokenAddress: tokenAddr,
            actionId: ACTION_ID,
            groupId: GROUP_ID,
            publisher: owner, // publisher is owner, not delegate
            delegate: delegateAddr,
            index: 0,
            blockNumber: block.number,
            timestamp: block.timestamp,
            content: "delegate content"
        });
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "delegate content");
    }

    // Reverse pagination tests
    function test_GetNotices_Reverse_Basic() public {
        vm.startPrank(owner);
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice0");
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice1");
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice2");
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice3");
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice4");
        vm.stopPrank();

        // Get latest 2 in reverse order
        (string[] memory c, , , , uint256 tc) = groupNotice.getNotices(
            tokenAddr,
            ACTION_ID,
            GROUP_ID,
            0,
            2,
            true
        );
        assertEq(tc, 5);
        assertEq(c.length, 2);
        assertEq(c[0], "notice4"); // latest first
        assertEq(c[1], "notice3");
    }

    function test_GetNotices_Reverse_WithOffset() public {
        vm.startPrank(owner);
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice0");
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice1");
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice2");
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice3");
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice4");
        vm.stopPrank();

        // Skip latest 1, get next 2 in reverse order
        (string[] memory c, , , , uint256 tc) = groupNotice.getNotices(
            tokenAddr,
            ACTION_ID,
            GROUP_ID,
            1,
            2,
            true
        );
        assertEq(tc, 5);
        assertEq(c.length, 2);
        assertEq(c[0], "notice3");
        assertEq(c[1], "notice2");
    }

    function test_GetNotices_Reverse_LessThanLimit() public {
        vm.startPrank(owner);
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice0");
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice1");
        vm.stopPrank();

        // Get all in reverse order with larger limit
        (string[] memory c, , , , uint256 tc) = groupNotice.getNotices(
            tokenAddr,
            ACTION_ID,
            GROUP_ID,
            0,
            10,
            true
        );
        assertEq(tc, 2);
        assertEq(c.length, 2);
        assertEq(c[0], "notice1");
        assertEq(c[1], "notice0");
    }

    // Boundary tests for validation
    function test_GetNotices_LimitZero_Reverts() public {
        vm.expectRevert(IGroupNoticeErrors.LimitZero.selector);
        groupNotice.getNotices(tokenAddr, ACTION_ID, GROUP_ID, 0, 0, false);
    }

    function test_GetNotices_Reverse_LimitZero_Reverts() public {
        vm.expectRevert(IGroupNoticeErrors.LimitZero.selector);
        groupNotice.getNotices(tokenAddr, ACTION_ID, GROUP_ID, 0, 0, true);
    }

    function test_GetNotices_Reverse_OffsetEqualsTotal_Reverts() public {
        vm.startPrank(owner);
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice0");
        vm.stopPrank();

        // offset == totalCount should revert
        vm.expectRevert(IGroupNoticeErrors.OffsetOutOfBounds.selector);
        groupNotice.getNotices(tokenAddr, ACTION_ID, GROUP_ID, 1, 10, true);
    }

    function test_GetNotices_Reverse_OffsetGreaterThanTotal_Reverts() public {
        vm.startPrank(owner);
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice0");
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice1");
        vm.stopPrank();

        // offset > totalCount should revert
        vm.expectRevert(IGroupNoticeErrors.OffsetOutOfBounds.selector);
        groupNotice.getNotices(tokenAddr, ACTION_ID, GROUP_ID, 3, 10, true);
    }

    function test_GetNotices_Reverse_ValidOffset_ReturnsCorrect() public {
        vm.startPrank(owner);
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice0");
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice1");
        groupNotice.publish(tokenAddr, ACTION_ID, GROUP_ID, "notice2");
        vm.stopPrank();

        // offset = 2 (third from end), should get only notice0
        (string[] memory c, , , , uint256 tc) = groupNotice.getNotices(
            tokenAddr,
            ACTION_ID,
            GROUP_ID,
            2,
            10,
            true
        );
        assertEq(tc, 3);
        assertEq(c.length, 1);
        assertEq(c[0], "notice0");
    }
}
