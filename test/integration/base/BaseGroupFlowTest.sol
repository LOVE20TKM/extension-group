// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    TestGroupFlowHelper,
    GroupUserParams,
    FlowUserParams
} from "../helper/TestGroupFlowHelper.sol";
import {FIRST_PARENT_TOKEN_FUNDRAISING_GOAL} from "@core-test/Constant.sol";
import {
    LOVE20ExtensionGroupAction
} from "../../../src/LOVE20ExtensionGroupAction.sol";
import {
    LOVE20ExtensionGroupService
} from "../../../src/LOVE20ExtensionGroupService.sol";

/// @title BaseGroupFlowTest
/// @notice Base contract for Group Flow integration tests with common setup and helpers
abstract contract BaseGroupFlowTest is Test {
    TestGroupFlowHelper public h;

    // Test users - Group owners (bob has 2 groups, alice and charlie have 1 each)
    GroupUserParams public bob;
    GroupUserParams public bob2; // bob's second group
    GroupUserParams public alice;
    GroupUserParams public charlie;

    // Regular flow users (for members) - 9 members for 3 groups × 3 members each
    FlowUserParams public member1;
    FlowUserParams public member2;
    FlowUserParams public member3;
    FlowUserParams public member4;
    FlowUserParams public member5;
    FlowUserParams public member6;
    FlowUserParams public member7;
    FlowUserParams public member8;
    FlowUserParams public member9;

    function setUp() public virtual {
        h = new TestGroupFlowHelper();

        // Complete launch phase first (required for real contracts)
        _finishLaunch();

        // Create group owners - they need to stake first to have gov votes
        bob = _createAndPrepareGroupUser("bob", "BobsGroup1");
        bob2 = _createAndPrepareGroupUser2("bob", "BobsGroup2", bob);
        alice = _createAndPrepareGroupUser("alice", "AlicesGroup");
        charlie = _createAndPrepareGroupUser("charlie", "CharliesGroup");

        // Create 9 regular members for 3 groups × 3 members each
        member1 = _createMember("member1");
        member2 = _createMember("member2");
        member3 = _createMember("member3");
        member4 = _createMember("member4");
        member5 = _createMember("member5");
        member6 = _createMember("member6");
        member7 = _createMember("member7");
        member8 = _createMember("member8");
        member9 = _createMember("member9");
    }

    function _createMember(
        string memory name
    ) internal returns (FlowUserParams memory) {
        return
            h.createUser(
                name,
                h.firstTokenAddress(),
                FIRST_PARENT_TOKEN_FUNDRAISING_GOAL / 10
            );
    }

    function _finishLaunch() internal {
        FlowUserParams memory launcher1 = h.createUser(
            "launcher1",
            h.firstTokenAddress(),
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
        );
        FlowUserParams memory launcher2 = h.createUser(
            "launcher2",
            h.firstTokenAddress(),
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
        );

        h.launch_contribute(launcher1);
        h.jump_second_half_min();
        h.launch_contribute(launcher2);
        h.launch_skip_claim_delay();
        h.launch_claim(launcher1);
        h.launch_claim(launcher2);
    }

    function _createAndPrepareGroupUser(
        string memory userName,
        string memory groupName
    ) internal returns (GroupUserParams memory user) {
        user = h.createGroupUser(
            userName,
            h.firstTokenAddress(),
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL,
            groupName
        );

        uint256 tokenAmount = 1_000_000_000 ether;
        h.forceMint(h.firstTokenAddress(), user.flow.userAddress, tokenAmount);

        h.stake_liquidity(user.flow);
        h.stake_token(user.flow);

        return user;
    }

    /// @notice Create second group for existing user (bob has 2 groups)
    function _createAndPrepareGroupUser2(
        string memory,
        string memory groupName,
        GroupUserParams memory existingUser
    ) internal returns (GroupUserParams memory user) {
        user.flow = existingUser.flow;
        user.stakeAmount = existingUser.stakeAmount;
        user.minJoinAmount = existingUser.minJoinAmount;
        user.maxJoinAmount = existingUser.maxJoinAmount;
        user.groupDescription = string(
            abi.encodePacked(groupName, " Description")
        );
        user.joinAmount = existingUser.joinAmount;
        user.scorePercent = existingUser.scorePercent;
        user.groupId = h.createGroupForExistingUser(user, groupName);
        return user;
    }
}

