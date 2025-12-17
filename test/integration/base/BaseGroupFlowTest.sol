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

    // Group owners - use internal to avoid stack too deep in auto-generated getter
    GroupUserParams internal bobGroup1;
    GroupUserParams internal bobGroup2;
    GroupUserParams internal aliceGroup;

    // Token source address for transfers
    address internal _tokenSourceAddress;

    // Lazy-loaded members
    mapping(uint256 => FlowUserParams) internal _members;
    mapping(uint256 => bool) internal _memberCreated;

    function setUp() public virtual {
        h = new TestGroupFlowHelper();
        _finishLaunch();
        _initBobGroup1();
        _initBobGroup2();
        _initAliceGroup();
    }

    function _initBobGroup1() internal {
        bobGroup1 = _createAndPrepareGroupUser("bob", "BobsGroup1");
    }

    function _initBobGroup2() internal {
        bobGroup2.flow = bobGroup1.flow;
        bobGroup2.stakeAmount = bobGroup1.stakeAmount;
        bobGroup2.minJoinAmount = bobGroup1.minJoinAmount;
        bobGroup2.maxJoinAmount = bobGroup1.maxJoinAmount;
        bobGroup2.groupDescription = "BobsGroup2 Description";
        bobGroup2.joinAmount = bobGroup1.joinAmount;
        bobGroup2.scorePercent = bobGroup1.scorePercent;
        bobGroup2.groupId = h.createGroupForExistingUser(bobGroup2, "BobsGroup2");
    }

    function _initAliceGroup() internal {
        aliceGroup = _createAndPrepareGroupUser("alice", "AlicesGroup");
    }

    /// @notice Get or create member by index (1-9)
    function getMember(uint256 index) public returns (FlowUserParams memory) {
        require(index >= 1 && index <= 9, "Invalid member index");
        if (!_memberCreated[index]) {
            _members[index] = h.createUser(
                string(abi.encodePacked("member", _uint2str(index))),
                h.firstTokenAddress(),
                FIRST_PARENT_TOKEN_FUNDRAISING_GOAL / 10
            );
            _memberCreated[index] = true;
        }
        return _members[index];
    }

    // Convenience accessors for members
    function member1() public returns (FlowUserParams memory) { return getMember(1); }
    function member2() public returns (FlowUserParams memory) { return getMember(2); }
    function member3() public returns (FlowUserParams memory) { return getMember(3); }
    function member4() public returns (FlowUserParams memory) { return getMember(4); }
    function member5() public returns (FlowUserParams memory) { return getMember(5); }
    function member6() public returns (FlowUserParams memory) { return getMember(6); }
    function member7() public returns (FlowUserParams memory) { return getMember(7); }
    function member8() public returns (FlowUserParams memory) { return getMember(8); }
    function member9() public returns (FlowUserParams memory) { return getMember(9); }

    function _uint2str(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        return string(buffer);
    }

    function _finishLaunch() internal {
        _doLaunchPhase1();
        _doLaunchPhase2();
    }

    function _doLaunchPhase1() internal {
        FlowUserParams memory launcher1 = h.createUser(
            "launcher1",
            h.firstTokenAddress(),
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
        );
        h.launch_contribute(launcher1);
        h.jump_second_half_min();
        _tokenSourceAddress = launcher1.userAddress;
    }

    function _doLaunchPhase2() internal {
        FlowUserParams memory launcher2 = h.createUser(
            "launcher2",
            h.firstTokenAddress(),
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
        );
        h.launch_contribute(launcher2);
        h.launch_skip_claim_delay();
        
        // Claim for both launchers
        FlowUserParams memory l1;
        l1.userAddress = _tokenSourceAddress;
        l1.tokenAddress = h.firstTokenAddress();
        h.launch_claim(l1);
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
        _transferAndStake(user);
        return user;
    }

    function _transferAndStake(GroupUserParams memory user) internal {
        uint256 tokenAmount = 100_000_000 ether;
        h.transferFrom(
            _tokenSourceAddress,
            h.firstTokenAddress(),
            user.flow.userAddress,
            tokenAmount
        );
        h.stake_liquidity(user.flow);
        h.stake_token(user.flow);
    }
}
