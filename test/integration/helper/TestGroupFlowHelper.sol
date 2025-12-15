// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ActionBody} from "@core/interfaces/ILOVE20Submit.sol";

// Extension mocks
import {MockERC20} from "@extension/test/mocks/MockERC20.sol";
import {MockStake} from "@extension/test/mocks/MockStake.sol";
import {MockJoin} from "@extension/test/mocks/MockJoin.sol";
import {MockVerify} from "@extension/test/mocks/MockVerify.sol";
import {MockMint} from "@extension/test/mocks/MockMint.sol";
import {MockSubmit} from "@extension/test/mocks/MockSubmit.sol";
import {MockLaunch} from "@extension/test/mocks/MockLaunch.sol";
import {MockVote} from "@extension/test/mocks/MockVote.sol";
import {MockRandom} from "@extension/test/mocks/MockRandom.sol";
import {MockUniswapV2Factory} from "@extension/test/mocks/MockUniswapV2Factory.sol";

// Extension center
import {LOVE20ExtensionCenter} from "@extension/src/LOVE20ExtensionCenter.sol";
import {ILOVE20ExtensionCenter} from "@extension/src/interface/ILOVE20ExtensionCenter.sol";

// Group contracts
import {LOVE20Group} from "@group/LOVE20Group.sol";
import {LOVE20GroupManager} from "../../../src/LOVE20GroupManager.sol";
import {LOVE20GroupDistrust} from "../../../src/LOVE20GroupDistrust.sol";
import {LOVE20ExtensionGroupActionFactory} from "../../../src/LOVE20ExtensionGroupActionFactory.sol";
import {LOVE20ExtensionGroupServiceFactory} from "../../../src/LOVE20ExtensionGroupServiceFactory.sol";
import {LOVE20ExtensionGroupAction} from "../../../src/LOVE20ExtensionGroupAction.sol";
import {LOVE20ExtensionGroupService} from "../../../src/LOVE20ExtensionGroupService.sol";
import {ILOVE20GroupManager} from "../../../src/interface/ILOVE20GroupManager.sol";

// Local mocks
import {MockGroupToken} from "../../mocks/MockGroupToken.sol";
import {MockGroup} from "../../mocks/MockGroup.sol";
import {MockVerifyExtended} from "../../mocks/MockVerifyExtended.sol";

// Constants
uint256 constant PHASE_BLOCKS = 10;

// User params structure
struct FlowUserParams {
    string userName;
    address userAddress;
    address tokenAddress;
    uint256 actionId;
    uint256 promisedWaitingPhases;
    SubmitParams submit;
    string[] verificationInfos;
    uint256 scorePercent;
}

struct SubmitParams {
    uint256 minStake;
    uint256 maxRandomAccounts;
    address whiteListAddress;
    string title;
    string verificationRule;
    string[] verificationKeys;
    string[] verificationInfoGuides;
}

// Group-specific user params
struct GroupUserParams {
    FlowUserParams flow;
    uint256 groupId;
    address groupActionAddress;
    address groupServiceAddress;
    uint256 groupActionId;
    uint256 groupServiceActionId;
    uint256 stakeAmount;
    uint256 minJoinAmount;
    uint256 maxJoinAmount;
    string groupDescription;
    uint256 joinAmount;
    uint256 scorePercent;
    address[] recipients;
    uint256[] basisPoints;
}

/// @title TestGroupFlowHelper
/// @notice Helper for group extension integration tests using mock contracts
contract TestGroupFlowHelper is Test {
    // ============ Mock Contracts ============

    MockGroupToken public token;
    MockGroup public group;
    MockStake public stake;
    MockJoin public join;
    MockVerifyExtended public verify;
    MockMint public mint;
    MockSubmit public submit;
    MockLaunch public launch;
    MockVote public mockVote;
    MockRandom public random;
    MockUniswapV2Factory public uniswapFactory;

    // ============ Extension Center ============

    LOVE20ExtensionCenter public extensionCenter;

    // ============ Group Contracts ============

    LOVE20GroupManager public groupManager;
    LOVE20GroupDistrust public groupDistrust;
    LOVE20ExtensionGroupActionFactory public groupActionFactory;
    LOVE20ExtensionGroupServiceFactory public groupServiceFactory;

    // ============ State ============

    address public firstTokenAddress;

    // ============ Constants ============

    uint256 constant DEFAULT_MIN_GOV_VOTE_RATIO_BPS = 100;
    uint256 constant DEFAULT_CAPACITY_MULTIPLIER = 10;
    uint256 constant DEFAULT_STAKING_MULTIPLIER = 100;
    uint256 constant DEFAULT_MAX_JOIN_AMOUNT_MULTIPLIER = 100;
    uint256 constant DEFAULT_MIN_JOIN_AMOUNT = 1e18;
    uint256 constant DEFAULT_STAKE_AMOUNT = 10000e18;
    uint256 constant DEFAULT_MAX_RECIPIENTS = 10;

    // ============ Constructor ============

    constructor() {
        _deployMockContracts();
        _deployGroupContracts();
    }

    function _deployMockContracts() internal {
        // Deploy mocks
        token = new MockGroupToken();
        group = new MockGroup();
        stake = new MockStake();
        join = new MockJoin();
        verify = new MockVerifyExtended();
        mint = new MockMint();
        submit = new MockSubmit();
        launch = new MockLaunch();
        mockVote = new MockVote();
        random = new MockRandom();
        uniswapFactory = new MockUniswapV2Factory();

        firstTokenAddress = address(token);

        // Setup initial state
        token.mint(address(this), 1_000_000e18);
        stake.setGovVotesNum(address(token), 100_000e18);
        verify.setCurrentRound(1);
        join.setCurrentRound(1);
    }

    function _deployGroupContracts() internal {
        // Deploy extension center
        extensionCenter = new LOVE20ExtensionCenter(
            address(uniswapFactory),
            address(launch),
            address(stake),
            address(submit),
            address(mockVote),
            address(join),
            address(verify),
            address(mint),
            address(random)
        );

        // Deploy group manager
        groupManager = new LOVE20GroupManager(
            address(extensionCenter),
            address(group),
            address(stake),
            address(join)
        );

        // Deploy group distrust
        groupDistrust = new LOVE20GroupDistrust(
            address(extensionCenter),
            address(verify),
            address(group)
        );

        // Deploy factories
        groupActionFactory = new LOVE20ExtensionGroupActionFactory(
            address(extensionCenter)
        );

        groupServiceFactory = new LOVE20ExtensionGroupServiceFactory(
            address(extensionCenter)
        );
    }

    // ============ User Creation ============

    function createUser(
        string memory userName,
        address tokenAddress,
        uint256 mintAmount
    ) public returns (FlowUserParams memory) {
        address userAddress = makeAddr(userName);

        FlowUserParams memory user;
        user.userName = userName;
        user.userAddress = userAddress;
        user.tokenAddress = tokenAddress;
        user.actionId = 0;
        user.promisedWaitingPhases = 4;
        user.scorePercent = 50;

        // Default submit params
        user.submit.minStake = 100;
        user.submit.maxRandomAccounts = 3;
        user.submit.whiteListAddress = address(0);
        user.submit.title = "default title";
        user.submit.verificationRule = "default verificationRule";
        user.submit.verificationKeys = new string[](1);
        user.submit.verificationKeys[0] = "default";
        user.submit.verificationInfoGuides = new string[](1);
        user.submit.verificationInfoGuides[0] = "default verificationInfoGuide";

        user.verificationInfos = new string[](1);
        user.verificationInfos[0] = "default verificationInfo";

        // Mint tokens
        if (mintAmount > 0) {
            token.mint(userAddress, mintAmount);
        }

        return user;
    }

    function createGroupUser(
        string memory userName,
        address tokenAddress,
        uint256 mintAmount,
        string memory groupName
    ) public returns (GroupUserParams memory) {
        FlowUserParams memory flowUser = createUser(userName, tokenAddress, mintAmount);

        GroupUserParams memory user;
        user.flow = flowUser;
        user.stakeAmount = DEFAULT_STAKE_AMOUNT;
        user.minJoinAmount = DEFAULT_MIN_JOIN_AMOUNT;
        user.maxJoinAmount = 0;
        user.groupDescription = string(abi.encodePacked(groupName, " Description"));
        user.joinAmount = DEFAULT_MIN_JOIN_AMOUNT * 10;
        user.scorePercent = 80;

        // Mint group NFT
        user.groupId = group.mint(flowUser.userAddress, groupName);

        // Setup governance votes
        stake.setValidGovVotes(tokenAddress, flowUser.userAddress, 10000e18);

        return user;
    }

    // ============ Phase Helpers ============

    function next_phase() public {
        uint256 newRound = verify.currentRound() + 1;
        verify.setCurrentRound(newRound);
        join.setCurrentRound(newRound);
    }

    function next_phases(uint256 num) public {
        for (uint256 i = 0; i < num; i++) {
            next_phase();
        }
    }

    // ============ Mock Setup Helpers ============

    function setupActionForVoting(
        address tokenAddress,
        uint256 actionId,
        address extensionAddress
    ) public {
        submit.setActionInfo(tokenAddress, actionId, extensionAddress);
        mockVote.setVotedActionIds(tokenAddress, verify.currentRound(), actionId);
        token.mint(extensionAddress, 1e18);
    }

    function setupGovVotes(
        address tokenAddress,
        address user,
        uint256 amount
    ) public {
        stake.setValidGovVotes(tokenAddress, user, amount);
    }

    function setupVerifyVotes(
        address voter,
        uint256 actionId,
        address extensionAddress,
        uint256 amount
    ) public {
        uint256 round = verify.currentRound();
        verify.setScoreByVerifierByActionIdByAccount(
            address(token),
            round,
            voter,
            actionId,
            extensionAddress,
            amount
        );
        uint256 currentTotal = verify.scoreByActionIdByAccount(
            address(token),
            round,
            actionId,
            extensionAddress
        );
        verify.setScoreByActionIdByAccount(
            address(token),
            round,
            actionId,
            extensionAddress,
            currentTotal + amount
        );
    }

    // ============ Group Action Helpers ============

    uint256 constant DEFAULT_JOIN_AMOUNT = 1e18;

    function group_action_create(GroupUserParams memory user) public returns (address) {
        // Ensure user has tokens for factory registration
        if (token.balanceOf(user.flow.userAddress) < DEFAULT_JOIN_AMOUNT) {
            token.mint(user.flow.userAddress, DEFAULT_JOIN_AMOUNT);
        }
        
        vm.startPrank(user.flow.userAddress);
        token.approve(address(groupActionFactory), DEFAULT_JOIN_AMOUNT);
        address extensionAddr = groupActionFactory.createExtension(
            user.flow.tokenAddress,
            address(groupManager),
            address(groupDistrust),
            user.flow.tokenAddress,
            DEFAULT_MIN_GOV_VOTE_RATIO_BPS,
            DEFAULT_CAPACITY_MULTIPLIER,
            DEFAULT_STAKING_MULTIPLIER,
            DEFAULT_MAX_JOIN_AMOUNT_MULTIPLIER,
            DEFAULT_MIN_JOIN_AMOUNT
        );
        vm.stopPrank();

        user.groupActionAddress = extensionAddr;
        return extensionAddr;
    }

    uint256 private _nextActionId = 1;
    
    function submit_group_action(GroupUserParams memory user) public returns (uint256 actionId) {
        // Use simple incrementing action ID
        actionId = _nextActionId++;
        
        // Setup action in mocks with correct current round
        uint256 currentRound = verify.currentRound();
        submit.setActionInfo(user.flow.tokenAddress, actionId, user.groupActionAddress);
        mockVote.setVotedActionIds(user.flow.tokenAddress, currentRound, actionId);
        
        // Mint tokens to extension for auto-initialization
        token.mint(user.groupActionAddress, DEFAULT_JOIN_AMOUNT);

        user.groupActionId = actionId;
        user.flow.actionId = actionId;
    }

    function vote(FlowUserParams memory user) public {
        // In mock environment, just ensure action is voted for
        // (already done in setupActionForVoting)
    }

    function group_activate(GroupUserParams memory user) public {
        address tokenAddress = user.flow.tokenAddress;
        
        // Setup action in current round for auto-initialization
        uint256 currentRound = verify.currentRound();
        submit.setActionInfo(tokenAddress, user.groupActionId, user.groupActionAddress);
        mockVote.setVotedActionIds(tokenAddress, currentRound, user.groupActionId);

        // Ensure user has tokens for staking
        if (IERC20(tokenAddress).balanceOf(user.flow.userAddress) < user.stakeAmount) {
            token.mint(user.flow.userAddress, user.stakeAmount);
        }

        vm.startPrank(user.flow.userAddress, user.flow.userAddress);
        IERC20(tokenAddress).approve(address(groupManager), user.stakeAmount);
        groupManager.activateGroup(
            tokenAddress,
            user.groupActionId,
            user.groupId,
            user.groupDescription,
            user.stakeAmount,
            user.minJoinAmount,
            user.maxJoinAmount,
            0
        );
        vm.stopPrank();
    }

    /// @notice Activate group without re-initializing (for subsequent activations)
    function group_activate_without_init(GroupUserParams memory user) public {
        address tokenAddress = user.flow.tokenAddress;

        // Ensure user has tokens for staking
        if (IERC20(tokenAddress).balanceOf(user.flow.userAddress) < user.stakeAmount) {
            token.mint(user.flow.userAddress, user.stakeAmount);
        }

        vm.startPrank(user.flow.userAddress, user.flow.userAddress);
        IERC20(tokenAddress).approve(address(groupManager), user.stakeAmount);
        groupManager.activateGroup(
            tokenAddress,
            user.groupActionId,
            user.groupId,
            user.groupDescription,
            user.stakeAmount,
            user.minJoinAmount,
            user.maxJoinAmount,
            0
        );
        vm.stopPrank();
    }

    function group_join(GroupUserParams memory member, GroupUserParams memory groupOwner) public {
        address tokenAddress = member.flow.tokenAddress;
        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(groupOwner.groupActionAddress);

        // Ensure member has tokens
        if (IERC20(tokenAddress).balanceOf(member.flow.userAddress) < member.joinAmount) {
            token.mint(member.flow.userAddress, member.joinAmount);
        }

        vm.startPrank(member.flow.userAddress);
        IERC20(tokenAddress).approve(address(groupAction), member.joinAmount);
        groupAction.join(groupOwner.groupId, member.joinAmount, new string[](0));
        vm.stopPrank();
    }

    function group_submit_score(
        GroupUserParams memory groupOwner,
        address[] memory,
        uint256[] memory scores
    ) public {
        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(groupOwner.groupActionAddress);

        vm.prank(groupOwner.flow.userAddress);
        groupAction.submitOriginScore(groupOwner.groupId, 0, scores);
    }

    function group_exit(GroupUserParams memory member, GroupUserParams memory groupOwner) public {
        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(groupOwner.groupActionAddress);

        vm.prank(member.flow.userAddress);
        groupAction.exit();
    }

    function group_expand(GroupUserParams memory groupOwner, uint256 additionalStake) public {
        address tokenAddress = groupOwner.flow.tokenAddress;
        token.mint(groupOwner.flow.userAddress, additionalStake);

        vm.startPrank(groupOwner.flow.userAddress, groupOwner.flow.userAddress);
        IERC20(tokenAddress).approve(address(groupManager), additionalStake);
        groupManager.expandGroup(
            tokenAddress,
            groupOwner.groupActionId,
            groupOwner.groupId,
            additionalStake
        );
        vm.stopPrank();
    }

    function group_deactivate(GroupUserParams memory groupOwner) public {
        vm.prank(groupOwner.flow.userAddress, groupOwner.flow.userAddress);
        groupManager.deactivateGroup(
            groupOwner.flow.tokenAddress,
            groupOwner.groupActionId,
            groupOwner.groupId
        );
    }

    // ============ Group Service Helpers ============

    function group_service_create(
        GroupUserParams memory user,
        address groupActionTokenAddress
    ) public returns (address) {
        // Ensure user has tokens for factory registration
        if (token.balanceOf(user.flow.userAddress) < DEFAULT_JOIN_AMOUNT) {
            token.mint(user.flow.userAddress, DEFAULT_JOIN_AMOUNT);
        }
        
        vm.startPrank(user.flow.userAddress);
        token.approve(address(groupServiceFactory), DEFAULT_JOIN_AMOUNT);
        address extensionAddr = groupServiceFactory.createExtension(
            user.flow.tokenAddress,
            groupActionTokenAddress,
            address(groupActionFactory),
            DEFAULT_MAX_RECIPIENTS
        );
        vm.stopPrank();

        user.groupServiceAddress = extensionAddr;
        return extensionAddr;
    }

    function submit_group_service_action(GroupUserParams memory user) public returns (uint256 actionId) {
        actionId = _nextActionId++;
        
        // Setup action in mocks with correct current round
        uint256 currentRound = verify.currentRound();
        submit.setActionInfo(user.flow.tokenAddress, actionId, user.groupServiceAddress);
        mockVote.setVotedActionIds(user.flow.tokenAddress, currentRound, actionId);
        
        // Mint tokens to extension for auto-initialization
        token.mint(user.groupServiceAddress, DEFAULT_JOIN_AMOUNT);

        user.groupServiceActionId = actionId;
    }

    function group_service_join(GroupUserParams memory groupOwner) public {
        LOVE20ExtensionGroupService groupService = LOVE20ExtensionGroupService(groupOwner.groupServiceAddress);

        vm.prank(groupOwner.flow.userAddress);
        groupService.join(new string[](0));
    }

    function group_service_set_recipients(GroupUserParams memory groupOwner) public {
        LOVE20ExtensionGroupService groupService = LOVE20ExtensionGroupService(groupOwner.groupServiceAddress);

        vm.prank(groupOwner.flow.userAddress);
        groupService.setRecipients(groupOwner.recipients, groupOwner.basisPoints);
    }

    function group_distrust_vote(
        GroupUserParams memory voter,
        GroupUserParams memory target,
        uint256 amount,
        string memory reason
    ) public {
        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(target.groupActionAddress);

        vm.prank(voter.flow.userAddress, voter.flow.userAddress);
        groupAction.distrustVote(target.flow.userAddress, amount, reason);
    }

    // ============ Utility ============

    function forceMint(address, address to, uint256 amount) public {
        token.mint(to, amount);
    }

    // ============ View Helpers ============

    function getGroupManager() public view returns (LOVE20GroupManager) {
        return groupManager;
    }

    function getGroupDistrust() public view returns (LOVE20GroupDistrust) {
        return groupDistrust;
    }

    function verifyContract() public view returns (MockVerifyExtended) {
        return verify;
    }
}
