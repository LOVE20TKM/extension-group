// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {ExtensionGroupAction} from "../src/ExtensionGroupAction.sol";
import {IGroupVerify} from "../src/interface/IGroupVerify.sol";
import {IGroupVerifyErrors} from "../src/interface/IGroupVerify.sol";
import {IGroupJoin} from "../src/interface/IGroupJoin.sol";
import {GroupVerify} from "../src/GroupVerify.sol";

/**
 * @title GroupVerifyBatchSubmissionTest
 * @notice Unit tests for batch submission of submitOriginScores
 */
contract GroupVerifyBatchSubmissionTest is BaseGroupTest {
    uint256 constant MAX_ORIGIN_SCORE = 100;

    ExtensionGroupAction public groupAction;
    uint256 public groupId1;

    function setUp() public {
        setUpBase();

        // Deploy the actual GroupAction contract
        groupAction = new ExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token),
            ACTIVATION_MIN_GOV_RATIO,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(token),
            MAX_JOIN_AMOUNT_RATIO
        );

        // Register extension
        token.mint(address(this), 1e18);
        token.approve(address(mockGroupActionFactory), type(uint256).max);
        mockGroupActionFactory.registerExtensionForTesting(
            address(groupAction),
            address(token)
        );

        // Setup group owner
        groupId1 = setupGroupOwner(groupOwner1, 10000e18, "TestGroup1");

        // Prepare extension init
        prepareExtensionInit(address(groupAction), address(token), ACTION_ID);

        // Activate group
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(groupAction),
            groupId1,
            "Group1",
            0,
            1e18,
            0,
            0
        );
    }

    function test_BatchSubmission_ThreeBatches() public {
        // Setup: 6 users join the group
        uint256[] memory joinAmounts = new uint256[](6);
        address[] memory users = new address[](6);
        for (uint256 i = 0; i < 6; i++) {
            users[i] = address(uint160(0x100 + i));
            joinAmounts[i] = (i + 1) * 10e18; // 10e18, 20e18, 30e18, 40e18, 50e18, 60e18
            setupUser(users[i], joinAmounts[i], address(groupJoin));

            vm.prank(users[i]);
            groupJoin.join(
                address(groupAction),
                groupId1,
                joinAmounts[i],
                new string[](0)
            );
        }

        uint256 round = verify.currentRound();
        uint256 accountCount = groupJoin.accountsByGroupIdCount(
            address(groupAction),
            round,
            groupId1
        );
        assertEq(accountCount, 6, "Should have 6 accounts");

        // Calculate expected total score manually
        // Batch 1: scores [80, 90] with amounts [10e18, 20e18]
        // Batch 2: scores [85, 95] with amounts [30e18, 40e18]
        // Batch 3: scores [75, 88] with amounts [50e18, 60e18]
        uint256 expectedTotalScore = 80 *
            10e18 +
            90 *
            20e18 +
            85 *
            30e18 +
            95 *
            40e18 +
            75 *
            50e18 +
            88 *
            60e18;

        // Batch 1: Submit first 2 accounts (startIndex = 0)
        uint256[] memory batch1 = new uint256[](2);
        batch1[0] = 80;
        batch1[1] = 90;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            batch1
        );

        // Verify state after batch 1
        assertEq(
            groupVerify.verifiedAccountCount(
                address(groupAction),
                round,
                groupId1
            ),
            2,
            "Verified count should be 2 after batch 1"
        );
        assertFalse(
            groupVerify.isVerified(address(groupAction), round, groupId1),
            "Should not be verified yet"
        );
        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round,
                users[0]
            ),
            80,
            "User 0 score should be 80"
        );
        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round,
                users[1]
            ),
            90,
            "User 1 score should be 90"
        );
        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round,
                users[2]
            ),
            0,
            "User 2 score should be 0 before verified"
        );
        {
            (bool found1, uint256 index1) = groupJoin.accountIndexByGroupId(
                address(groupAction),
                groupId1,
                users[1],
                round
            );
            assertTrue(found1, "User 1 should be found");
            assertEq(index1, 1, "User 1 should be at index 1");
        }
        {
            (bool found2, uint256 index2) = groupJoin.accountIndexByGroupId(
                address(groupAction),
                groupId1,
                users[2],
                round
            );
            assertTrue(found2, "User 2 should be found");
            assertTrue(index2 > 1, "User 2 should be out of range [0,1]");
        }
        {
            (bool found0, ) = groupJoin.accountIndexByGroupId(
                address(groupAction),
                groupId1,
                users[0],
                round
            );
            assertTrue(found0, "User 0 should be found");
        }

        // Batch 2: Submit next 2 accounts (startIndex = 2)
        uint256[] memory batch2 = new uint256[](2);
        batch2[0] = 85;
        batch2[1] = 95;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            2,
            batch2
        );

        // Verify state after batch 2
        assertEq(
            groupVerify.verifiedAccountCount(
                address(groupAction),
                round,
                groupId1
            ),
            4,
            "Verified count should be 4 after batch 2"
        );
        assertFalse(
            groupVerify.isVerified(address(groupAction), round, groupId1),
            "Should not be verified yet"
        );
        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round,
                users[2]
            ),
            85,
            "User 2 score should be 85"
        );
        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round,
                users[3]
            ),
            95,
            "User 3 score should be 95"
        );

        // Batch 3: Submit last 2 accounts (startIndex = 4)
        uint256[] memory batch3 = new uint256[](2);
        batch3[0] = 75;
        batch3[1] = 88;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            4,
            batch3
        );

        // Verify final state after batch 3
        assertEq(
            groupVerify.verifiedAccountCount(
                address(groupAction),
                round,
                groupId1
            ),
            6,
            "Verified count should be 6 after batch 3"
        );
        assertTrue(
            groupVerify.isVerified(address(groupAction), round, groupId1),
            "Should be verified after all batches"
        );
        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round,
                users[4]
            ),
            75,
            "User 4 score should be 75"
        );
        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round,
                users[5]
            ),
            88,
            "User 5 score should be 88"
        );

        // Verify total score matches expected
        uint256 actualTotalScore = groupVerify.totalAccountScore(
            address(groupAction),
            round,
            groupId1
        );
        assertEq(
            actualTotalScore,
            expectedTotalScore,
            "Total score should match expected"
        );
    }

    function test_BatchSubmission_InvalidStartIndex() public {
        // Setup: 3 users join
        address[] memory users = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            users[i] = address(uint160(0x100 + i));
            setupUser(users[i], 10e18, address(groupJoin));

            vm.prank(users[i]);
            groupJoin.join(
                address(groupAction),
                groupId1,
                10e18,
                new string[](0)
            );
        }

        // Submit first batch
        uint256[] memory batch1 = new uint256[](2);
        batch1[0] = 80;
        batch1[1] = 90;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            batch1
        );

        // Try to submit with wrong startIndex (should be 2, but using 1)
        uint256[] memory batch2 = new uint256[](1);
        batch2[0] = 85;

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupVerifyErrors.InvalidStartIndex.selector);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            1,
            batch2
        );
    }

    function test_BatchSubmission_ScoresExceedAccountCount() public {
        // Setup: 2 users join
        address[] memory users = new address[](2);
        for (uint256 i = 0; i < 2; i++) {
            users[i] = address(uint160(0x100 + i));
            setupUser(users[i], 10e18, address(groupJoin));

            vm.prank(users[i]);
            groupJoin.join(
                address(groupAction),
                groupId1,
                10e18,
                new string[](0)
            );
        }

        // Try to submit more scores than accounts (startIndex = 0, but 3 scores for 2 accounts)
        uint256[] memory scores = new uint256[](3);
        scores[0] = 80;
        scores[1] = 90;
        scores[2] = 85;

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupVerifyErrors.ScoresExceedAccountCount.selector);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores
        );
    }

    function test_BatchSubmission_PartialBatchExceedsAccountCount() public {
        // Setup: 3 users join
        address[] memory users = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            users[i] = address(uint160(0x100 + i));
            setupUser(users[i], 10e18, address(groupJoin));

            vm.prank(users[i]);
            groupJoin.join(
                address(groupAction),
                groupId1,
                10e18,
                new string[](0)
            );
        }

        // Submit first batch
        uint256[] memory batch1 = new uint256[](2);
        batch1[0] = 80;
        batch1[1] = 90;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            batch1
        );

        // Try to submit batch that exceeds remaining accounts (startIndex = 2, but 2 scores when only 1 account remains)
        uint256[] memory batch2 = new uint256[](2);
        batch2[0] = 85;
        batch2[1] = 95;

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupVerifyErrors.ScoresExceedAccountCount.selector);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            2,
            batch2
        );
    }

    function test_BatchSubmission_SingleBatchCompletes() public {
        // Setup: 3 users join
        address[] memory users = new address[](3);
        uint256[] memory joinAmounts = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            users[i] = address(uint160(0x100 + i));
            joinAmounts[i] = (i + 1) * 10e18;
            setupUser(users[i], joinAmounts[i], address(groupJoin));

            vm.prank(users[i]);
            groupJoin.join(
                address(groupAction),
                groupId1,
                joinAmounts[i],
                new string[](0)
            );
        }

        uint256 round = verify.currentRound();

        // Calculate expected total score
        uint256 expectedTotalScore = 80 * 10e18 + 90 * 20e18 + 85 * 30e18;

        // Submit all scores in one batch
        uint256[] memory scores = new uint256[](3);
        scores[0] = 80;
        scores[1] = 90;
        scores[2] = 85;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores
        );

        // Verify completion
        assertEq(
            groupVerify.verifiedAccountCount(
                address(groupAction),
                round,
                groupId1
            ),
            3,
            "Verified count should be 3"
        );
        assertTrue(
            groupVerify.isVerified(address(groupAction), round, groupId1),
            "Should be verified after single batch"
        );

        // Verify total score
        uint256 actualTotalScore = groupVerify.totalAccountScore(
            address(groupAction),
            round,
            groupId1
        );
        assertEq(
            actualTotalScore,
            expectedTotalScore,
            "Total score should match expected"
        );
    }

    function test_BatchSubmission_MultipleBatchesWithDifferentSizes() public {
        // Setup: 10 users join
        address[] memory users = new address[](10);
        uint256[] memory joinAmounts = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            users[i] = address(uint160(0x100 + i));
            joinAmounts[i] = (i + 1) * 10e18;
            setupUser(users[i], joinAmounts[i], address(groupJoin));

            vm.prank(users[i]);
            groupJoin.join(
                address(groupAction),
                groupId1,
                joinAmounts[i],
                new string[](0)
            );
        }

        uint256 round = verify.currentRound();

        // Calculate expected total score manually
        uint256 expectedTotalScore = 0;
        for (uint256 i = 0; i < 10; i++) {
            uint256 score = 80 + (i % 3); // 80, 81, 82, 80, 81, 82, 80, 81, 82, 80
            expectedTotalScore += score * joinAmounts[i];
        }

        // Batch 1: Submit 3 accounts (startIndex = 0)
        uint256[] memory batch1 = new uint256[](3);
        batch1[0] = 80;
        batch1[1] = 81;
        batch1[2] = 82;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            batch1
        );

        assertEq(
            groupVerify.verifiedAccountCount(
                address(groupAction),
                round,
                groupId1
            ),
            3,
            "Verified count should be 3 after batch 1"
        );

        // Batch 2: Submit 5 accounts (startIndex = 3)
        uint256[] memory batch2 = new uint256[](5);
        batch2[0] = 80;
        batch2[1] = 81;
        batch2[2] = 82;
        batch2[3] = 80;
        batch2[4] = 81;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            3,
            batch2
        );

        assertEq(
            groupVerify.verifiedAccountCount(
                address(groupAction),
                round,
                groupId1
            ),
            8,
            "Verified count should be 8 after batch 2"
        );

        // Batch 3: Submit remaining 2 accounts (startIndex = 8)
        uint256[] memory batch3 = new uint256[](2);
        batch3[0] = 82;
        batch3[1] = 80;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            8,
            batch3
        );

        // Verify final state
        assertEq(
            groupVerify.verifiedAccountCount(
                address(groupAction),
                round,
                groupId1
            ),
            10,
            "Verified count should be 10 after batch 3"
        );
        assertTrue(
            groupVerify.isVerified(address(groupAction), round, groupId1),
            "Should be verified after all batches"
        );

        // Verify total score
        uint256 actualTotalScore = groupVerify.totalAccountScore(
            address(groupAction),
            round,
            groupId1
        );
        assertEq(
            actualTotalScore,
            expectedTotalScore,
            "Total score should match expected"
        );
    }

    function test_BatchSubmission_AlreadyVerified() public {
        // Setup: 2 users join
        address[] memory users = new address[](2);
        for (uint256 i = 0; i < 2; i++) {
            users[i] = address(uint160(0x100 + i));
            setupUser(users[i], 10e18, address(groupJoin));

            vm.prank(users[i]);
            groupJoin.join(
                address(groupAction),
                groupId1,
                10e18,
                new string[](0)
            );
        }

        // Submit all scores in one batch
        uint256[] memory scores = new uint256[](2);
        scores[0] = 80;
        scores[1] = 90;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores
        );

        // Try to submit again after verification is complete
        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 85;

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupVerifyErrors.AlreadyVerified.selector);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores2
        );
    }

    function test_BatchSubmission_WithMaxScore() public {
        // Setup: 4 users join
        address[] memory users = new address[](4);
        uint256[] memory joinAmounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            users[i] = address(uint160(0x100 + i));
            joinAmounts[i] = (i + 1) * 10e18;
            setupUser(users[i], joinAmounts[i], address(groupJoin));

            vm.prank(users[i]);
            groupJoin.join(
                address(groupAction),
                groupId1,
                joinAmounts[i],
                new string[](0)
            );
        }

        uint256 round = verify.currentRound();

        // Calculate expected total score (some scores are MAX_ORIGIN_SCORE = 100)
        uint256 expectedTotalScore = 80 *
            10e18 +
            MAX_ORIGIN_SCORE *
            20e18 +
            85 *
            30e18 +
            MAX_ORIGIN_SCORE *
            40e18;

        // Batch 1: Submit first 2 accounts
        uint256[] memory batch1 = new uint256[](2);
        batch1[0] = 80;
        batch1[1] = MAX_ORIGIN_SCORE;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            batch1
        );

        // Verify scores (MAX_ORIGIN_SCORE should be stored correctly)
        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round,
                users[0]
            ),
            80,
            "User 0 score should be 80"
        );
        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round,
                users[1]
            ),
            MAX_ORIGIN_SCORE,
            "User 1 score should be MAX_ORIGIN_SCORE"
        );

        // Batch 2: Submit last 2 accounts
        uint256[] memory batch2 = new uint256[](2);
        batch2[0] = 85;
        batch2[1] = MAX_ORIGIN_SCORE;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            2,
            batch2
        );

        // Verify final state
        assertTrue(
            groupVerify.isVerified(address(groupAction), round, groupId1),
            "Should be verified after all batches"
        );

        // Verify total score
        uint256 actualTotalScore = groupVerify.totalAccountScore(
            address(groupAction),
            round,
            groupId1
        );
        assertEq(
            actualTotalScore,
            expectedTotalScore,
            "Total score should match expected"
        );
    }
}
