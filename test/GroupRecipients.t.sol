// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {GroupRecipients} from "../src/GroupRecipients.sol";
import {
    IGroupRecipients,
    IGroupRecipientsErrors,
    IGroupRecipientsEvents
} from "../src/interface/IGroupRecipients.sol";

/**
 * @title GroupRecipientsTest
 * @notice Unit tests for GroupRecipients contract
 */
contract GroupRecipientsTest is BaseGroupTest, IGroupRecipientsEvents {
    GroupRecipients public groupRecipients;

    uint256 constant PRECISION = 1e18;
    uint256 constant ACTION_1 = 1;
    uint256 constant ACTION_2 = 2;

    uint256 public groupId1;
    uint256 public groupId2;

    function setUp() public {
        setUpBase();
        groupRecipients = new GroupRecipients(address(mockGroupActionFactory));

        // Mint group NFTs to owners
        groupId1 = group.mint(groupOwner1, "Group1");
        groupId2 = group.mint(groupOwner1, "Group2");
    }

    // ============================================================
    // Helper: build single-element arrays
    // ============================================================

    function _addr(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    function _uint(uint256 v) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = v;
    }

    function _addrs(
        address a,
        address b
    ) internal pure returns (address[] memory arr) {
        arr = new address[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function _uints(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function _addrs3(
        address a,
        address b,
        address c
    ) internal pure returns (address[] memory arr) {
        arr = new address[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }

    function _uints3(
        uint256 a,
        uint256 b,
        uint256 c
    ) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }

    function _emptyAddrs() internal pure returns (address[] memory) {
        return new address[](0);
    }

    function _emptyUints() internal pure returns (uint256[] memory) {
        return new uint256[](0);
    }

    function _remark(string memory s) internal pure returns (string[] memory arr) {
        arr = new string[](1);
        arr[0] = s;
    }

    function _remarks(string memory a, string memory b) internal pure returns (string[] memory arr) {
        arr = new string[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function _remarks3(string memory a, string memory b, string memory c) internal pure returns (string[] memory arr) {
        arr = new string[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }

    function _emptyRemarks() internal pure returns (string[] memory) {
        return new string[](0);
    }

    // ============================================================
    // 1. getDistribution precise numerical tests
    // ============================================================

    function test_getDistribution_singleRecipient_50percent() public {
        // Set single recipient with 50% ratio
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _addr(user1),
            _uint(50e16), // 50% = 0.5e18
            _remark("")
        );

        uint256 round = verify.currentRound();
        (
            address[] memory addrs,
            uint256[] memory ratios,
            uint256[] memory amounts,
            uint256 ownerAmount
        ) = groupRecipients.getDistribution(
                groupOwner1,
                address(token),
                ACTION_1,
                groupId1,
                100e18, // groupReward
                round
            );

        assertEq(addrs.length, 1, "addrs length");
        assertEq(addrs[0], user1, "recipient addr");
        assertEq(ratios[0], 50e16, "ratio");
        assertEq(amounts[0], 50e18, "amount = 50% of 100e18");
        assertEq(ownerAmount, 50e18, "ownerAmount = remainder");
    }

    function test_getDistribution_multipleRecipients() public {
        // 30% + 20% + 10% = 60% total
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _addrs3(user1, user2, user3),
            _uints3(30e16, 20e16, 10e16),
            _remarks3("", "", "")
        );

        uint256 round = verify.currentRound();
        (
            ,
            ,
            uint256[] memory amounts,
            uint256 ownerAmount
        ) = groupRecipients.getDistribution(
                groupOwner1,
                address(token),
                ACTION_1,
                groupId1,
                1000e18,
                round
            );

        assertEq(amounts[0], 300e18, "user1: 30% of 1000e18");
        assertEq(amounts[1], 200e18, "user2: 20% of 1000e18");
        assertEq(amounts[2], 100e18, "user3: 10% of 1000e18");
        assertEq(ownerAmount, 400e18, "owner: 40% remaining");
    }

    function test_getDistribution_rounding() public {
        // 33.33% = 333300000000000000 (0.3333e18)
        uint256 ratio = 333300000000000000;

        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _addr(user1),
            _uint(ratio),
            _remark("")
        );

        uint256 round = verify.currentRound();
        (
            ,
            ,
            uint256[] memory amounts,
            uint256 ownerAmount
        ) = groupRecipients.getDistribution(
                groupOwner1,
                address(token),
                ACTION_1,
                groupId1,
                100e18,
                round
            );

        // amount = 100e18 * 333300000000000000 / 1e18 = 33330000000000000000 = 33.33e18
        uint256 expectedAmount = (100e18 * ratio) / PRECISION;
        assertEq(amounts[0], expectedAmount, "amount with rounding");
        // ownerAmount absorbs remainder
        assertEq(
            ownerAmount,
            100e18 - expectedAmount,
            "ownerAmount absorbs remainder"
        );
        assertTrue(ownerAmount > 0, "ownerAmount should be positive");
    }

    function test_getDistribution_maxRatio_100percent() public {
        // 100% = 1e18
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _addr(user1),
            _uint(PRECISION),
            _remark("")
        );

        uint256 round = verify.currentRound();
        (
            ,
            ,
            uint256[] memory amounts,
            uint256 ownerAmount
        ) = groupRecipients.getDistribution(
                groupOwner1,
                address(token),
                ACTION_1,
                groupId1,
                100e18,
                round
            );

        assertEq(amounts[0], 100e18, "recipient gets all");
        assertEq(ownerAmount, 0, "owner gets nothing");
    }

    function test_getDistribution_zeroReward() public {
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _addrs(user1, user2),
            _uints(50e16, 50e16),
            _remarks("", "")
        );

        uint256 round = verify.currentRound();
        (
            ,
            ,
            uint256[] memory amounts,
            uint256 ownerAmount
        ) = groupRecipients.getDistribution(
                groupOwner1,
                address(token),
                ACTION_1,
                groupId1,
                0, // zero reward
                round
            );

        assertEq(amounts[0], 0, "zero reward -> zero amount[0]");
        assertEq(amounts[1], 0, "zero reward -> zero amount[1]");
        assertEq(ownerAmount, 0, "zero reward -> zero ownerAmount");
    }

    // ============================================================
    // 2. Clear and re-set recipients
    // ============================================================

    function test_clearRecipients() public {
        // First set recipients
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _addr(user1),
            _uint(50e16),
            _remark("")
        );

        uint256 round = verify.currentRound();

        // Verify recipients are set
        (address[] memory addrs, , string[] memory remarks) = groupRecipients.recipients(
            groupOwner1,
            address(token),
            ACTION_1,
            groupId1,
            round
        );
        assertEq(addrs.length, 1, "should have 1 recipient");
        remarks;

        // Clear by setting empty arrays
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _emptyAddrs(),
            _emptyUints(),
            _emptyRemarks()
        );

        // Verify recipients are cleared
        (address[] memory addrsAfter, , string[] memory remarksAfter) = groupRecipients.recipients(
            groupOwner1,
            address(token),
            ACTION_1,
            groupId1,
            round
        );
        assertEq(addrsAfter.length, 0, "should have 0 recipients after clear");
        remarksAfter;
    }

    function test_clearThenResetRecipients() public {
        uint256 round = verify.currentRound();

        // Set initial recipients
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _addr(user1),
            _uint(50e16),
            _remark("")
        );

        // Clear
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _emptyAddrs(),
            _emptyUints(),
            _emptyRemarks()
        );

        // Re-set with different recipients
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _addrs(user2, user3),
            _uints(30e16, 20e16),
            _remarks("", "")
        );

        (address[] memory addrs, uint256[] memory ratios, string[] memory remarks) = groupRecipients
            .recipients(
                groupOwner1,
                address(token),
                ACTION_1,
                groupId1,
                round
            );

        assertEq(addrs.length, 2, "should have 2 recipients after re-set");
        remarks;
        assertEq(addrs[0], user2, "first recipient");
        assertEq(addrs[1], user3, "second recipient");
        assertEq(ratios[0], 30e16, "first ratio");
        assertEq(ratios[1], 20e16, "second ratio");
    }

    // ============================================================
    // 3. Cross-round recipients history
    // ============================================================

    function test_crossRoundHistory() public {
        // Round 1: set recipients
        uint256 round1 = verify.currentRound();
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _addr(user1),
            _uint(50e16),
            _remark("")
        );

        // Advance to round 2
        advanceRound();
        uint256 round2 = verify.currentRound();

        // Round 2: set different recipients
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _addrs(user2, user3),
            _uints(30e16, 20e16),
            _remarks("", "")
        );

        // Query round 1: should return round 1 recipients
        (address[] memory addrsR1, uint256[] memory ratiosR1, string[] memory remarksR1) = groupRecipients
            .recipients(
                groupOwner1,
                address(token),
                ACTION_1,
                groupId1,
                round1
            );
        assertEq(addrsR1.length, 1, "round 1: 1 recipient");
        assertEq(addrsR1[0], user1, "round 1: user1");
        assertEq(ratiosR1[0], 50e16, "round 1: 50%");
        remarksR1;

        // Query round 2: should return round 2 recipients
        (address[] memory addrsR2, uint256[] memory ratiosR2, string[] memory remarksR2) = groupRecipients
            .recipients(
                groupOwner1,
                address(token),
                ACTION_1,
                groupId1,
                round2
            );
        assertEq(addrsR2.length, 2, "round 2: 2 recipients");
        assertEq(addrsR2[0], user2, "round 2: user2");
        assertEq(addrsR2[1], user3, "round 2: user3");
        assertEq(ratiosR2[0], 30e16, "round 2: 30%");
        assertEq(ratiosR2[1], 20e16, "round 2: 20%");
        remarksR2;
    }

    // ============================================================
    // 4. actionIdsWithRecipients / groupIdsByActionIdWithRecipients tracking
    // ============================================================

    function test_tracking_addActionAndGroup() public {
        uint256 round = verify.currentRound();

        // Set recipients for actionId=1, groupId=1
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _addr(user1),
            _uint(50e16),
            _remark("")
        );

        // actionId=1 should be tracked
        uint256[] memory actionIds = groupRecipients.actionIdsWithRecipients(
            groupOwner1,
            address(token),
            round
        );
        assertEq(actionIds.length, 1, "1 action tracked");
        assertEq(actionIds[0], ACTION_1, "action 1 tracked");

        // groupId=1 should be tracked under actionId=1
        uint256[] memory groupIds = groupRecipients
            .groupIdsByActionIdWithRecipients(
                groupOwner1,
                address(token),
                ACTION_1,
                round
            );
        assertEq(groupIds.length, 1, "1 group tracked");
        assertEq(groupIds[0], groupId1, "group 1 tracked");
    }

    function test_tracking_multipleGroupsUnderSameAction() public {
        uint256 round = verify.currentRound();

        // Set recipients for actionId=1, groupId=1
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _addr(user1),
            _uint(50e16),
            _remark("")
        );

        // Set recipients for actionId=1, groupId=2
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId2,
            _addr(user2),
            _uint(40e16),
            _remark("")
        );

        // Both groupIds tracked
        uint256[] memory groupIds = groupRecipients
            .groupIdsByActionIdWithRecipients(
                groupOwner1,
                address(token),
                ACTION_1,
                round
            );
        assertEq(groupIds.length, 2, "2 groups tracked");
    }

    function test_tracking_clearOneGroupKeepsOther() public {
        uint256 round = verify.currentRound();

        // Set recipients for both groups under action 1
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _addr(user1),
            _uint(50e16),
            _remark("")
        );
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId2,
            _addr(user2),
            _uint(40e16),
            _remark("")
        );

        // Clear groupId1
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _emptyAddrs(),
            _emptyUints(),
            _emptyRemarks()
        );

        // groupId2 still tracked
        uint256[] memory groupIds = groupRecipients
            .groupIdsByActionIdWithRecipients(
                groupOwner1,
                address(token),
                ACTION_1,
                round
            );
        assertEq(groupIds.length, 1, "only 1 group tracked");
        assertEq(groupIds[0], groupId2, "group 2 still tracked");

        // actionId still tracked (because groupId2 remains)
        uint256[] memory actionIds = groupRecipients.actionIdsWithRecipients(
            groupOwner1,
            address(token),
            round
        );
        assertEq(actionIds.length, 1, "action still tracked");
        assertEq(actionIds[0], ACTION_1, "action 1 still tracked");
    }

    function test_tracking_clearAllGroupsRemovesAction() public {
        uint256 round = verify.currentRound();

        // Set recipients for both groups under action 1
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _addr(user1),
            _uint(50e16),
            _remark("")
        );
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId2,
            _addr(user2),
            _uint(40e16),
            _remark("")
        );

        // Clear groupId1
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            _emptyAddrs(),
            _emptyUints(),
            _emptyRemarks()
        );

        // Clear groupId2
        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId2,
            _emptyAddrs(),
            _emptyUints(),
            _emptyRemarks()
        );

        // No groups tracked
        uint256[] memory groupIds = groupRecipients
            .groupIdsByActionIdWithRecipients(
                groupOwner1,
                address(token),
                ACTION_1,
                round
            );
        assertEq(groupIds.length, 0, "no groups tracked");

        // actionId removed from tracking
        uint256[] memory actionIds = groupRecipients.actionIdsWithRecipients(
            groupOwner1,
            address(token),
            round
        );
        assertEq(actionIds.length, 0, "no actions tracked");
    }

    // ============================================================
    // 5. Event emission test
    // ============================================================

    function test_setRecipients_emitsEvent() public {
        uint256 round = verify.currentRound();
        address[] memory addrs = _addrs(user1, user2);
        uint256[] memory ratios = _uints(30e16, 20e16);

        string[] memory remarks = _remarks("", "");
        vm.expectEmit(true, true, true, true);
        emit SetRecipients({
            tokenAddress: address(token),
            round: round,
            actionId: ACTION_1,
            groupId: groupId1,
            account: groupOwner1,
            recipients: addrs,
            ratios: ratios,
            remarks: remarks
        });

        vm.prank(groupOwner1);
        groupRecipients.setRecipients(
            address(token),
            ACTION_1,
            groupId1,
            addrs,
            ratios,
            remarks
        );
    }
}
