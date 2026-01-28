// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupFlowTest} from "./base/BaseGroupFlowTest.sol";
import {
    GroupUserParams,
    FlowUserParams
} from "./helper/TestGroupFlowHelper.sol";
import {ExtensionGroupAction} from "../../src/ExtensionGroupAction.sol";
import {ExtensionGroupService} from "../../src/ExtensionGroupService.sol";
import {IGroupJoin} from "../../src/interface/IGroupJoin.sol";
import {IGroupVerify} from "../../src/interface/IGroupVerify.sol";

/// @title GroupServiceMultiChildIntegrationTest
/// @notice Parent token creates group service actions for multiple child communities
contract GroupServiceMultiChildIntegrationTest is BaseGroupFlowTest {
    uint256 internal constant CHILD_TOKEN_COUNT = 3;
    uint256 internal constant ACTIONS_PER_CHILD = 3;
    uint256 internal constant GROUPS_PER_ACTION = 3;
    uint256 internal constant MEMBERS_PER_GROUP_1 = 2;
    uint256 internal constant MEMBERS_PER_GROUP_2 = 3;
    uint256 internal constant MEMBERS_PER_GROUP_3 = 4;

    struct ChildCommunity {
        address tokenAddress;
        address serviceExtension;
        uint256 serviceActionId;
        GroupUserParams[GROUPS_PER_ACTION] owners;
        address[ACTIONS_PER_CHILD] actionExtensions;
        uint256[ACTIONS_PER_CHILD] actionIds;
        FlowUserParams[9] members;
    }

    function test_parent_service_multi_child_multi_action_flow() public {
        _prepareLaunchEligibility(bobGroup1.flow.userAddress);
        GroupUserParams memory carolGroup = _createAndPrepareGroupUser(
            "carol",
            "CarolsGroup"
        );

        ChildCommunity[CHILD_TOKEN_COUNT] memory children;
        address[CHILD_TOKEN_COUNT] memory childTokens;
        childTokens[0] = _launchChildToken("CHD1", 3);
        childTokens[1] = _launchChildToken("CHD2", 2);
        childTokens[2] = _launchChildToken("CHD3", 1);

        children[0] = _initChildCommunity(0, childTokens[0]);
        children[1] = _initChildCommunity(1, childTokens[1]);
        children[2] = _initChildCommunity(2, childTokens[2]);

        GroupUserParams[CHILD_TOKEN_COUNT] memory serviceSubmitters;
        serviceSubmitters[0] = bobGroup1;
        serviceSubmitters[1] = aliceGroup;
        serviceSubmitters[2] = carolGroup;
        _createServiceActions(children, serviceSubmitters);
        _createGroupActions(children);

        // === Join Phase ===
        h.next_phase();
        _activateGroups(children);
        _joinGroups(children);
        _joinServices(children);

        // === Verify Phase ===
        h.next_phase();
        uint256 verifyRound = h.verifyContract().currentRound();
        _submitGroupScores(children);
        _coreVerifyGroupActions(children);
        _coreVerifyServiceActions(children, serviceSubmitters);

        // === Assert ===
        _assertGroupJoins(children);
        _assertServiceJoins(children);
        _assertVerifierCounts(children, verifyRound);
    }

    function _prepareLaunchEligibility(address launcher) internal {
        uint256 minGovMints = h
            .launchContract()
            .MIN_GOV_REWARD_MINTS_TO_LAUNCH();
        uint256 requiredMints = CHILD_TOKEN_COUNT * minGovMints;
        _setMintGovRewardCount(h.firstTokenAddress(), launcher, requiredMints);
        assertEq(
            h.mintContract().numOfMintGovRewardByAccount(
                h.firstTokenAddress(),
                launcher
            ),
            requiredMints,
            "mint gov reward count mismatch"
        );
        assertEq(
            h.launchContract().remainingLaunchCount(
                h.firstTokenAddress(),
                launcher
            ),
            CHILD_TOKEN_COUNT,
            "remaining launch count mismatch"
        );
    }

    function _setMintGovRewardCount(
        address tokenAddress,
        address account,
        uint256 count
    ) internal {
        bytes32 outer = keccak256(abi.encode(tokenAddress, uint256(3)));
        bytes32 slot = keccak256(abi.encode(account, outer));
        vm.store(address(h.mintContract()), slot, bytes32(count));
    }

    function _initChildCommunity(
        uint256 index,
        address tokenAddress
    ) internal returns (ChildCommunity memory child) {
        child.tokenAddress = tokenAddress;
        _finishChildLaunch(tokenAddress, index);
        child.owners = _createChildOwners(child.tokenAddress, index);
        child.members = _createChildMembers(child.tokenAddress, index);
    }

    function _launchChildToken(
        string memory symbol,
        uint256 expectedRemaining
    ) internal returns (address childToken) {
        assertEq(
            h.launchContract().remainingLaunchCount(
                h.firstTokenAddress(),
                bobGroup1.flow.userAddress
            ),
            expectedRemaining,
            "remaining launch count mismatch"
        );
        vm.startPrank(bobGroup1.flow.userAddress);
        childToken = h.launchContract().launchToken(
            symbol,
            h.firstTokenAddress()
        );
        vm.stopPrank();
    }

    function _finishChildLaunch(address childToken, uint256 index) internal {
        FlowUserParams memory launcher1 = h.createUser(
            _childUserName("launcher1", index),
            childToken,
            h.launchContract().PARENT_TOKEN_FUNDRAISING_GOAL()
        );
        FlowUserParams memory launcher2 = h.createUser(
            _childUserName("launcher2", index),
            childToken,
            h.launchContract().PARENT_TOKEN_FUNDRAISING_GOAL()
        );

        h.launch_contribute(launcher1);
        h.jump_second_half_min();
        h.launch_contribute(launcher2);
        h.launch_skip_claim_delay();
        h.launch_claim(launcher1);
        h.launch_claim(launcher2);
    }

    function _createChildOwners(
        address childToken,
        uint256 index
    ) internal returns (GroupUserParams[GROUPS_PER_ACTION] memory owners) {
        owners[0] = _createChildOwner(childToken, index, "ownerA");
        owners[1] = _createChildOwner(childToken, index, "ownerB");
        owners[2] = _createChildOwner(childToken, index, "ownerC");
    }

    function _createChildOwner(
        address childToken,
        uint256 index,
        string memory label
    ) internal returns (GroupUserParams memory owner) {
        owner = h.createGroupUser(
            _childUserName(label, index),
            h.firstTokenAddress(),
            h.launchContract().PARENT_TOKEN_FUNDRAISING_GOAL(),
            _childGroupName(label, index)
        );
        owner.flow.tokenAddress = childToken;
        h.forceMint(
            h.firstTokenAddress(),
            owner.flow.userAddress,
            100_000_000 ether
        );
        h.forceMint(childToken, owner.flow.userAddress, 100_000_000 ether);
        h.stake_liquidity(owner.flow);
        h.stake_token(owner.flow);
    }

    function _createChildMembers(
        address childToken,
        uint256 index
    ) internal returns (FlowUserParams[9] memory members) {
        for (uint256 i; i < 9; i++) {
            members[i] = h.createUser(
                _childMemberName(index, i + 1),
                childToken,
                h.launchContract().PARENT_TOKEN_FUNDRAISING_GOAL() / 10
            );
        }
    }

    function _createServiceActions(
        ChildCommunity[CHILD_TOKEN_COUNT] memory children,
        GroupUserParams[CHILD_TOKEN_COUNT] memory submitters
    ) internal {
        for (uint256 i; i < CHILD_TOKEN_COUNT; i++) {
            GroupUserParams memory submitter = submitters[i];
            address serviceExt = h.group_service_create(
                submitter,
                children[i].tokenAddress
            );
            submitter.groupServiceAddress = serviceExt;
            uint256 actionId = h.submit_group_service_action(submitter);

            FlowUserParams memory voter = submitter.flow;
            voter.actionId = actionId;
            _voteOnce(voter);

            children[i].serviceExtension = serviceExt;
            children[i].serviceActionId = actionId;
        }
    }

    function _createGroupActions(
        ChildCommunity[CHILD_TOKEN_COUNT] memory children
    ) internal {
        for (uint256 i; i < CHILD_TOKEN_COUNT; i++) {
            for (uint256 a; a < ACTIONS_PER_CHILD; a++) {
                GroupUserParams memory creator = children[i].owners[a];
                address actionExt = h.group_action_create(creator);
                creator.groupActionAddress = actionExt;
                uint256 actionId = h.submit_group_action(creator);

                children[i].actionExtensions[a] = actionExt;
                children[i].actionIds[a] = actionId;

                for (uint256 g; g < GROUPS_PER_ACTION; g++) {
                    children[i].owners[g].groupActionAddress = actionExt;
                    children[i].owners[g].groupActionId = actionId;

                    FlowUserParams memory voter = children[i].owners[g].flow;
                    voter.actionId = actionId;
                    _voteOnce(voter);
                }
            }
        }
    }

    function _voteOnce(FlowUserParams memory voter) internal {
        voter.vote.voteNum = 100;
        voter.vote.votePercent = 0;
        h.vote(voter);
    }

    function _activateGroups(
        ChildCommunity[CHILD_TOKEN_COUNT] memory children
    ) internal {
        for (uint256 i; i < CHILD_TOKEN_COUNT; i++) {
            for (uint256 a; a < ACTIONS_PER_CHILD; a++) {
                address actionExt = children[i].actionExtensions[a];
                uint256 actionId = children[i].actionIds[a];
                for (uint256 g; g < GROUPS_PER_ACTION; g++) {
                    children[i].owners[g].groupActionAddress = actionExt;
                    children[i].owners[g].groupActionId = actionId;
                    h.group_activate(children[i].owners[g]);
                }
            }
        }
    }

    function _joinGroups(
        ChildCommunity[CHILD_TOKEN_COUNT] memory children
    ) internal {
        for (uint256 i; i < CHILD_TOKEN_COUNT; i++) {
            for (uint256 a; a < ACTIONS_PER_CHILD; a++) {
                address actionExt = children[i].actionExtensions[a];
                uint256 actionId = children[i].actionIds[a];
                _joinGroupMembers(
                    children[i],
                    actionExt,
                    actionId,
                    0,
                    MEMBERS_PER_GROUP_1
                );
                _joinGroupMembers(
                    children[i],
                    actionExt,
                    actionId,
                    1,
                    MEMBERS_PER_GROUP_2
                );
                _joinGroupMembers(
                    children[i],
                    actionExt,
                    actionId,
                    2,
                    MEMBERS_PER_GROUP_3
                );
            }
        }
    }

    function _joinGroupMembers(
        ChildCommunity memory child,
        address actionExt,
        uint256 actionId,
        uint256 groupIndex,
        uint256 memberCount
    ) internal {
        GroupUserParams memory owner = child.owners[groupIndex];
        owner.groupActionAddress = actionExt;
        owner.groupActionId = actionId;

        for (uint256 i; i < memberCount; i++) {
            GroupUserParams memory member;
            member.flow = child.members[_memberIndex(groupIndex, i)];
            member.joinAmount = (2 + i) * 1e18;
            member.groupActionAddress = actionExt;
            h.group_join(member, owner);
        }
    }

    function _joinServices(
        ChildCommunity[CHILD_TOKEN_COUNT] memory children
    ) internal {
        for (uint256 i; i < CHILD_TOKEN_COUNT; i++) {
            for (uint256 g; g < GROUPS_PER_ACTION; g++) {
                children[i].owners[g].groupServiceAddress = children[i]
                    .serviceExtension;
                children[i].owners[g].groupServiceActionId = children[i]
                    .serviceActionId;
                h.group_service_join(children[i].owners[g]);
            }
        }
    }

    function _submitGroupScores(
        ChildCommunity[CHILD_TOKEN_COUNT] memory children
    ) internal {
        for (uint256 i; i < CHILD_TOKEN_COUNT; i++) {
            for (uint256 a; a < ACTIONS_PER_CHILD; a++) {
                address actionExt = children[i].actionExtensions[a];
                uint256 actionId = children[i].actionIds[a];
                for (uint256 g; g < GROUPS_PER_ACTION; g++) {
                    children[i].owners[g].groupActionAddress = actionExt;
                    children[i].owners[g].groupActionId = actionId;
                    h.group_submit_score(
                        children[i].owners[g],
                        _scoresForGroup(g)
                    );
                }
            }
        }
    }

    function _scoresForGroup(
        uint256 groupIndex
    ) internal pure returns (uint256[] memory scores) {
        uint256 count = groupIndex == 0
            ? MEMBERS_PER_GROUP_1
            : (groupIndex == 1 ? MEMBERS_PER_GROUP_2 : MEMBERS_PER_GROUP_3);
        scores = new uint256[](count);
        for (uint256 i; i < count; i++) {
            scores[i] = 100 - (i * 10);
        }
    }

    function _coreVerifyGroupActions(
        ChildCommunity[CHILD_TOKEN_COUNT] memory children
    ) internal {
        for (uint256 i; i < CHILD_TOKEN_COUNT; i++) {
            for (uint256 a; a < ACTIONS_PER_CHILD; a++) {
                address actionExt = children[i].actionExtensions[a];
                uint256 actionId = children[i].actionIds[a];
                for (uint256 g; g < GROUPS_PER_ACTION; g++) {
                    children[i].owners[g].groupActionAddress = actionExt;
                    children[i].owners[g].groupActionId = actionId;
                    h.core_verify_extension(children[i].owners[g], actionExt);
                }
            }
        }
    }

    function _coreVerifyServiceActions(
        ChildCommunity[CHILD_TOKEN_COUNT] memory children,
        GroupUserParams[CHILD_TOKEN_COUNT] memory submitters
    ) internal {
        for (uint256 i; i < CHILD_TOKEN_COUNT; i++) {
            FlowUserParams memory verifier = submitters[i].flow;
            h.core_verify_extension(
                verifier,
                h.firstTokenAddress(),
                children[i].serviceActionId,
                children[i].serviceExtension
            );
        }
    }

    function _assertGroupJoins(
        ChildCommunity[CHILD_TOKEN_COUNT] memory children
    ) internal view {
        IGroupJoin groupJoin = IGroupJoin(
            h.groupActionFactory().GROUP_JOIN_ADDRESS()
        );
        for (uint256 i; i < CHILD_TOKEN_COUNT; i++) {
            for (uint256 a; a < ACTIONS_PER_CHILD; a++) {
                address actionExt = children[i].actionExtensions[a];
                for (uint256 g; g < GROUPS_PER_ACTION; g++) {
                    uint256 expectedCount = g == 0
                        ? MEMBERS_PER_GROUP_1
                        : (g == 1 ? MEMBERS_PER_GROUP_2 : MEMBERS_PER_GROUP_3);
                    assertEq(
                        groupJoin.accountsByGroupIdCount(
                            actionExt,
                            h.joinContract().currentRound(),
                            children[i].owners[g].groupId
                        ),
                        expectedCount,
                        "group members count mismatch"
                    );
                }
            }
        }
    }

    function _assertServiceJoins(
        ChildCommunity[CHILD_TOKEN_COUNT] memory children
    ) internal view {
        for (uint256 i; i < CHILD_TOKEN_COUNT; i++) {
            ExtensionGroupAction anyAction = ExtensionGroupAction(
                children[i].actionExtensions[0]
            );
            uint256 stakeAmount = anyAction.ACTIVATION_STAKE_AMOUNT();
            uint256 expectedTotal = ACTIONS_PER_CHILD *
                GROUPS_PER_ACTION *
                stakeAmount;
            ExtensionGroupService service = ExtensionGroupService(
                children[i].serviceExtension
            );
            assertEq(
                service.joinedAmount(),
                expectedTotal,
                "service joinedAmount mismatch"
            );
            for (uint256 g; g < GROUPS_PER_ACTION; g++) {
                uint256 expectedByOwner = ACTIONS_PER_CHILD * stakeAmount;
                assertEq(
                    service.joinedAmountByAccount(
                        children[i].owners[g].flow.userAddress
                    ),
                    expectedByOwner,
                    "service joinedAmountByAccount mismatch"
                );
            }
        }
    }

    function _assertVerifierCounts(
        ChildCommunity[CHILD_TOKEN_COUNT] memory children,
        uint256 verifyRound
    ) internal view {
        IGroupVerify groupVerify = IGroupVerify(
            h.groupActionFactory().GROUP_VERIFY_ADDRESS()
        );
        for (uint256 i; i < CHILD_TOKEN_COUNT; i++) {
            for (uint256 a; a < ACTIONS_PER_CHILD; a++) {
                assertEq(
                    groupVerify.verifiersCount(
                        children[i].actionExtensions[a],
                        verifyRound
                    ),
                    GROUPS_PER_ACTION,
                    "group action verifiers count mismatch"
                );
            }
        }
    }

    function _childUserName(
        string memory prefix,
        uint256 index
    ) internal pure returns (string memory) {
        return string(abi.encodePacked("child", _uint2str(index), "_", prefix));
    }

    function _childGroupName(
        string memory prefix,
        uint256 index
    ) internal pure returns (string memory) {
        return string(abi.encodePacked("C", _uint2str(index), "_", prefix));
    }

    function _childMemberName(
        uint256 index,
        uint256 memberIndex
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "child",
                    _uint2str(index),
                    "_member",
                    _uint2str(memberIndex)
                )
            );
    }

    function _memberIndex(
        uint256 groupIndex,
        uint256 offset
    ) internal pure returns (uint256) {
        if (groupIndex == 0) return offset;
        if (groupIndex == 1) return MEMBERS_PER_GROUP_1 + offset;
        return MEMBERS_PER_GROUP_1 + MEMBERS_PER_GROUP_2 + offset;
    }
}
