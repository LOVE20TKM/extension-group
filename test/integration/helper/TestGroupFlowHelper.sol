// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Core contracts and interfaces
import {
    IUniswapV2Factory
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Factory.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {ILOVE20Launch} from "@core/interfaces/ILOVE20Launch.sol";
import {ILOVE20Stake} from "@core/interfaces/ILOVE20Stake.sol";
import {
    ILOVE20Submit,
    ActionBody,
    ActionInfo
} from "@core/interfaces/ILOVE20Submit.sol";
import {ILOVE20Vote} from "@core/interfaces/ILOVE20Vote.sol";
import {ILOVE20Join} from "@core/interfaces/ILOVE20Join.sol";
import {ILOVE20Verify} from "@core/interfaces/ILOVE20Verify.sol";
import {ILOVE20Mint} from "@core/interfaces/ILOVE20Mint.sol";
import {ILOVE20SLToken} from "@core/interfaces/ILOVE20SLToken.sol";
import {ILOVE20STToken} from "@core/interfaces/ILOVE20STToken.sol";
import {IETH20} from "@core/WETH/IETH20.sol";

// Core implementations
import {LOVE20TokenFactory} from "@core/LOVE20TokenFactory.sol";
import {LOVE20Launch} from "@core/LOVE20Launch.sol";
import {LOVE20Stake} from "@core/LOVE20Stake.sol";
import {LOVE20Submit} from "@core/LOVE20Submit.sol";
import {LOVE20Vote} from "@core/LOVE20Vote.sol";
import {LOVE20Join} from "@core/LOVE20Join.sol";
import {LOVE20Random} from "@core/LOVE20Random.sol";
import {LOVE20Verify} from "@core/LOVE20Verify.sol";
import {LOVE20Mint} from "@core/LOVE20Mint.sol";

// Extension center
import {LOVE20ExtensionCenter} from "@extension/src/LOVE20ExtensionCenter.sol";

// Group contracts
import {LOVE20Group} from "@group/LOVE20Group.sol";
import {LOVE20GroupManager} from "../../../src/LOVE20GroupManager.sol";
import {LOVE20GroupDistrust} from "../../../src/LOVE20GroupDistrust.sol";
import {
    LOVE20ExtensionGroupActionFactory
} from "../../../src/LOVE20ExtensionGroupActionFactory.sol";
import {
    LOVE20ExtensionGroupServiceFactory
} from "../../../src/LOVE20ExtensionGroupServiceFactory.sol";
import {
    LOVE20ExtensionGroupAction
} from "../../../src/LOVE20ExtensionGroupAction.sol";
import {
    LOVE20ExtensionGroupService
} from "../../../src/LOVE20ExtensionGroupService.sol";

// Precompiled bytecode
import {PrecompiledBytecodes} from "../../artifacts/PrecompiledBytecodes.sol";

// Core test helper for params structs
import {
    FlowUserParams,
    LaunchParams,
    StakeParams,
    SubmitParams,
    VoteParams,
    JoinParams,
    VerifyParams
} from "@core-test/helper/TestBaseCore.sol";
import {
    FIRST_PARENT_TOKEN_FUNDRAISING_GOAL,
    PHASE_BLOCKS,
    SECOND_HALF_MIN_BLOCKS
} from "@core-test/Constant.sol";

// Group-specific user params
struct GroupUserParams {
    FlowUserParams flow;
    uint256 groupId;
    address groupActionAddress;
    address groupServiceAddress;
    uint256 groupActionId;
    uint256 groupServiceActionId;
    uint256 stakeAmount;
    uint256 maxCapacity;
    uint256 minJoinAmount;
    uint256 maxJoinAmount;
    string groupDescription;
    uint256 joinAmount;
    uint256 scorePercent;
    address[] recipients;
    uint256[] basisPoints;
}

interface IMintable {
    function mint(address to, uint256 amount) external;
}

/// @title TestGroupFlowHelper
/// @notice Helper for group extension integration tests using REAL contracts
contract TestGroupFlowHelper is Test {
    // ============ Core Contracts ============

    IUniswapV2Factory public uniswapV2Factory;
    address public rootParentTokenAddress;
    address public firstTokenAddress;
    ILOVE20Launch public launchContract;
    ILOVE20Stake public stakeContract;
    ILOVE20Submit public submitContract;
    ILOVE20Vote public voteContract;
    ILOVE20Join public joinContract;
    address public randomAddress;
    ILOVE20Verify public verifyContract;
    ILOVE20Mint public mintContract;

    // ============ Extension Center ============

    LOVE20ExtensionCenter public extensionCenter;

    // ============ Group Contracts ============

    LOVE20Group public group;
    LOVE20GroupManager public groupManager;
    LOVE20GroupDistrust public groupDistrust;
    LOVE20ExtensionGroupActionFactory public groupActionFactory;
    LOVE20ExtensionGroupServiceFactory public groupServiceFactory;

    // ============ Constants ============

    uint256 constant DEFAULT_MIN_GOV_VOTE_RATIO_BPS = 1; // 0.0001%
    uint256 constant DEFAULT_GROUP_ACTIVATION_STAKE_AMOUNT = 1000e18;
    uint256 constant DEFAULT_MAX_JOIN_AMOUNT_MULTIPLIER = 100;
    uint256 constant DEFAULT_MAX_RECIPIENTS = 10;
    uint256 constant DEFAULT_JOIN_AMOUNT = 1e18;
    uint256 constant DEFAULT_GROUP_MIN_JOIN_AMOUNT = 1e18;

    // Core constants
    uint256 constant TOKEN_SYMBOL_LENGTH = 4;
    string constant FIRST_TOKEN_SYMBOL = "LOVE";
    uint256 constant PARENT_TOKEN_FUNDRAISING_GOAL = 10000 ether;
    uint256 constant MAX_SUPPLY = 21_000_000_000 ether;
    uint256 constant LAUNCH_AMOUNT = 6_300_000_000 ether;
    uint256 constant WITHDRAW_WAITING_BLOCKS = 100;
    uint256 constant MIN_GOV_REWARD_MINTS_TO_LAUNCH = 10;
    uint256 constant MAX_WITHDRAWABLE_TO_FEE_RATIO = 16;
    uint256 constant JOIN_END_PHASE_BLOCKS = 1;
    uint256 constant PROMISED_WAITING_PHASES_MIN = 2;
    uint256 constant PROMISED_WAITING_PHASES_MAX = 24;
    uint256 constant SUBMIT_MIN_PER_THOUSAND = 20;
    uint256 constant MAX_VERIFICATION_KEY_LENGTH = 6;
    uint256 constant RANDOM_SEED_UPDATE_MIN_PER_TEN_THOUSAND = 5;
    uint256 constant ACTION_REWARD_MIN_VOTE_PER_THOUSAND = 100;
    uint256 constant ROUND_REWARD_GOV_PER_THOUSAND = 200;
    uint256 constant ROUND_REWARD_ACTION_PER_THOUSAND = 800;
    uint256 constant MAX_GOV_BOOST_REWARD_MULTIPLIER = 100;

    // Group NFT parameters
    uint256 constant GROUP_BASE_DIVISOR = 1e8;
    uint256 constant GROUP_BYTES_THRESHOLD = 8;
    uint256 constant GROUP_MULTIPLIER = 10;
    uint256 constant GROUP_MAX_NAME_LENGTH = 64;

    // Storage for test values
    mapping(string => uint256) internal _beforeValues;

    // ============ Constructor ============

    constructor() {
        _deployAllContracts();
    }

    function _deployAllContracts() internal {
        // 1. Deploy WETH using precompiled bytecode
        rootParentTokenAddress = _deployETH20("Wrapped ETH", "WETH");

        // 2. Deploy UniswapV2Factory using precompiled bytecode
        address uniswapFactoryAddr = _deployUniswapV2Factory(address(0));
        uniswapV2Factory = IUniswapV2Factory(uniswapFactoryAddr);

        // 3. Deploy LOVE20 core contracts
        _deployLOVE20Contracts();

        // 4. Deploy extension center
        _deployExtensionCenter();

        // 5. Deploy group contracts
        _deployGroupContracts();
    }

    function _deployETH20(
        string memory name,
        string memory symbol
    ) internal returns (address weth) {
        bytes memory bytecode = PrecompiledBytecodes.getETH20Bytecode();
        bytes memory initCode = abi.encodePacked(
            bytecode,
            abi.encode(name, symbol)
        );
        assembly {
            weth := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(weth != address(0), "ETH20 deployment failed");
    }

    function _deployUniswapV2Factory(
        address feeToSetter
    ) internal returns (address factory) {
        bytes memory bytecode = PrecompiledBytecodes
            .getUniswapV2FactoryBytecode();
        bytes memory initCode = abi.encodePacked(
            bytecode,
            abi.encode(feeToSetter)
        );
        assembly {
            factory := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(factory != address(0), "UniswapV2Factory deployment failed");
    }

    function _deployLOVE20Contracts() internal {
        uint256 currentBlock = block.number;

        // Deploy token factory
        LOVE20TokenFactory tokenFactory = new LOVE20TokenFactory();

        // Deploy launch
        LOVE20Launch launch = new LOVE20Launch();
        launchContract = ILOVE20Launch(address(launch));

        // Deploy stake
        LOVE20Stake stake = new LOVE20Stake(currentBlock, PHASE_BLOCKS);
        stakeContract = ILOVE20Stake(address(stake));

        // Deploy submit
        LOVE20Submit submit = new LOVE20Submit(currentBlock, PHASE_BLOCKS);
        submitContract = ILOVE20Submit(address(submit));

        // Deploy vote
        LOVE20Vote vote_ = new LOVE20Vote(currentBlock, PHASE_BLOCKS);
        voteContract = ILOVE20Vote(address(vote_));

        // Deploy join (starts at phase 1)
        LOVE20Join join_ = new LOVE20Join(
            currentBlock + PHASE_BLOCKS,
            PHASE_BLOCKS
        );
        joinContract = ILOVE20Join(address(join_));

        // Deploy random (starts at phase 1)
        LOVE20Random random_ = new LOVE20Random(
            currentBlock + PHASE_BLOCKS,
            PHASE_BLOCKS
        );
        randomAddress = address(random_);

        // Deploy verify (starts at phase 2)
        LOVE20Verify verify_ = new LOVE20Verify(
            currentBlock + 2 * PHASE_BLOCKS,
            PHASE_BLOCKS
        );
        verifyContract = ILOVE20Verify(address(verify_));

        // Deploy mint
        LOVE20Mint mint_ = new LOVE20Mint();
        mintContract = ILOVE20Mint(address(mint_));

        // Initialize token factory
        tokenFactory.initialize(
            address(uniswapV2Factory),
            address(launchContract),
            address(stakeContract),
            address(mintContract),
            LAUNCH_AMOUNT,
            MAX_SUPPLY,
            MAX_WITHDRAWABLE_TO_FEE_RATIO
        );

        // Initialize launch
        launch.initialize(
            address(tokenFactory),
            address(submitContract),
            address(mintContract),
            TOKEN_SYMBOL_LENGTH,
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL,
            PARENT_TOKEN_FUNDRAISING_GOAL,
            SECOND_HALF_MIN_BLOCKS,
            WITHDRAW_WAITING_BLOCKS,
            MIN_GOV_REWARD_MINTS_TO_LAUNCH
        );

        // Launch first token
        firstTokenAddress = launch.launchToken(
            FIRST_TOKEN_SYMBOL,
            rootParentTokenAddress
        );

        // Initialize stake
        stake.initialize(
            PROMISED_WAITING_PHASES_MIN,
            PROMISED_WAITING_PHASES_MAX
        );

        // Initialize submit
        submit.initialize(
            address(stakeContract),
            SUBMIT_MIN_PER_THOUSAND,
            MAX_VERIFICATION_KEY_LENGTH
        );

        // Initialize vote
        vote_.initialize(address(stakeContract), address(submitContract));

        // Initialize join
        join_.initialize(
            address(submitContract),
            address(voteContract),
            randomAddress,
            JOIN_END_PHASE_BLOCKS
        );

        // Initialize random
        random_.initialize(address(verifyContract));

        // Initialize verify
        verify_.initialize(
            randomAddress,
            firstTokenAddress,
            address(stakeContract),
            address(voteContract),
            address(joinContract),
            address(mintContract),
            RANDOM_SEED_UPDATE_MIN_PER_TEN_THOUSAND
        );

        // Initialize mint
        mint_.initialize(
            address(voteContract),
            address(verifyContract),
            address(stakeContract),
            ACTION_REWARD_MIN_VOTE_PER_THOUSAND,
            ROUND_REWARD_GOV_PER_THOUSAND,
            ROUND_REWARD_ACTION_PER_THOUSAND,
            MAX_GOV_BOOST_REWARD_MULTIPLIER
        );
    }

    function _deployExtensionCenter() internal {
        extensionCenter = new LOVE20ExtensionCenter(
            address(uniswapV2Factory),
            address(launchContract),
            address(stakeContract),
            address(submitContract),
            address(voteContract),
            address(joinContract),
            address(verifyContract),
            address(mintContract),
            randomAddress
        );
    }

    function _deployGroupContracts() internal {
        // Deploy LOVE20Group NFT
        group = new LOVE20Group(
            firstTokenAddress,
            GROUP_BASE_DIVISOR,
            GROUP_BYTES_THRESHOLD,
            GROUP_MULTIPLIER,
            GROUP_MAX_NAME_LENGTH
        );

        // Deploy group manager
        groupManager = new LOVE20GroupManager(
            address(extensionCenter),
            address(group),
            address(stakeContract),
            address(joinContract)
        );

        // Deploy group distrust
        groupDistrust = new LOVE20GroupDistrust(
            address(extensionCenter),
            address(verifyContract),
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
        uint256 mintAmountOfParentToken
    ) public returns (FlowUserParams memory user) {
        address userAddress = makeAddr(userName);
        
        user.userName = userName;
        user.userAddress = userAddress;
        user.tokenAddress = tokenAddress;
        
        _initUserLaunchParams(user, userAddress);
        _initUserStakeParams(user);
        _initUserSubmitParams(user);
        _initUserVoteParams(user);
        _initUserJoinParams(user);
        _initUserVerifyParams(user);
        _mintParentTokens(tokenAddress, userAddress, mintAmountOfParentToken);
    }

    function _initUserLaunchParams(FlowUserParams memory user, address userAddress) internal pure {
        user.launch.contributeParentTokenAmountPercent = 50;
        user.launch.contributeToAddress = userAddress;
    }

    function _initUserStakeParams(FlowUserParams memory user) internal pure {
        user.stake.tokenAmountForLpPercent = 50;
        user.stake.parentTokenAmountForLpPercent = 50;
        user.stake.tokenAmountPercent = 50;
        user.stake.promisedWaitingPhases = 4;
    }

    function _initUserSubmitParams(FlowUserParams memory user) internal pure {
        user.submit.minStake = 100;
        user.submit.maxRandomAccounts = 3;
        user.submit.title = "default title";
        user.submit.verificationRule = "default verificationRule";
        user.submit.verificationKeys = new string[](1);
        user.submit.verificationKeys[0] = "key1";
        user.submit.verificationInfoGuides = new string[](1);
        user.submit.verificationInfoGuides[0] = "guide1";
    }

    function _initUserVoteParams(FlowUserParams memory user) internal pure {
        user.vote.votePercent = 100;
    }

    function _initUserJoinParams(FlowUserParams memory user) internal pure {
        user.join.tokenAmountPercent = 50;
        user.join.additionalTokenAmountPercent = 50;
        user.join.verificationInfos = new string[](1);
        user.join.verificationInfos[0] = "default verificationInfo";
        user.join.updateVerificationInfos = new string[](1);
        user.join.updateVerificationInfos[0] = "updated verificationInfo";
        user.join.rounds = 4;
    }

    function _initUserVerifyParams(FlowUserParams memory user) internal pure {
        user.verify.scorePercent = 50;
    }

    function _mintParentTokens(
        address tokenAddress,
        address userAddress,
        uint256 mintAmount
    ) internal {
        address parentTokenAddress = ILOVE20Token(tokenAddress).parentTokenAddress();
        if (parentTokenAddress == rootParentTokenAddress) {
            vm.deal(userAddress, mintAmount);
            vm.startPrank(userAddress);
            IETH20(rootParentTokenAddress).deposit{value: mintAmount}();
            vm.stopPrank();
        } else {
            forceMint(parentTokenAddress, userAddress, mintAmount);
        }
    }

    function createGroupUser(
        string memory userName,
        address tokenAddress,
        uint256 mintAmountOfParentToken,
        string memory groupName
    ) public returns (GroupUserParams memory user) {
        user.flow = createUser(userName, tokenAddress, mintAmountOfParentToken);
        _initGroupUserParams(user, groupName);
        _mintGroupNFT(user, tokenAddress, groupName);
    }

    function _initGroupUserParams(
        GroupUserParams memory user,
        string memory groupName
    ) internal pure {
        user.stakeAmount = DEFAULT_GROUP_ACTIVATION_STAKE_AMOUNT;
        user.minJoinAmount = DEFAULT_GROUP_MIN_JOIN_AMOUNT;
        user.groupDescription = string(abi.encodePacked(groupName, " Description"));
        user.joinAmount = DEFAULT_GROUP_MIN_JOIN_AMOUNT * 10;
        user.scorePercent = 80;
    }

    function _mintGroupNFT(
        GroupUserParams memory user,
        address tokenAddress,
        string memory groupName
    ) internal {
        uint256 mintCost = group.calculateMintCost(groupName);
        address userAddress = user.flow.userAddress;
        
        if (mintCost > IERC20(tokenAddress).balanceOf(userAddress)) {
            forceMint(tokenAddress, userAddress, mintCost);
        }

        vm.startPrank(userAddress);
        if (mintCost > 0) {
            IERC20(tokenAddress).approve(address(group), mintCost);
        }
        user.groupId = group.mint(groupName);
        vm.stopPrank();
    }

    /// @notice Create additional group for existing user (same user can own multiple groups)
    function createGroupForExistingUser(
        GroupUserParams memory existingUser,
        string memory groupName
    ) public returns (uint256 groupId) {
        address userAddress = existingUser.flow.userAddress;
        address tokenAddress = existingUser.flow.tokenAddress;

        uint256 mintCost = group.calculateMintCost(groupName);
        IERC20 token = IERC20(tokenAddress);

        if (mintCost > token.balanceOf(userAddress)) {
            forceMint(tokenAddress, userAddress, mintCost);
        }

        vm.startPrank(userAddress);
        if (mintCost > 0) {
            token.approve(address(group), mintCost);
        }
        groupId = group.mint(groupName);
        vm.stopPrank();
    }

    // ============ Utility Functions ============

    function forceMint(
        address tokenAddress,
        address to,
        uint256 amount
    ) public {
        if (tokenAddress != rootParentTokenAddress) {
            vm.startPrank(ILOVE20Token(tokenAddress).minter());
            IMintable(tokenAddress).mint(to, amount);
            vm.stopPrank();
        } else {
            IMintable(tokenAddress).mint(to, amount);
        }
    }

    function transfer(
        FlowUserParams memory from,
        address tokenAddress,
        address to,
        uint256 amount
    ) public {
        vm.startPrank(from.userAddress);
        IERC20(tokenAddress).transfer(to, amount);
        vm.stopPrank();
    }

    function transferFrom(
        address from,
        address tokenAddress,
        address to,
        uint256 amount
    ) public {
        vm.startPrank(from);
        IERC20(tokenAddress).transfer(to, amount);
        vm.stopPrank();
    }

    function next_phase() public {
        vm.roll(block.number + PHASE_BLOCKS);
    }

    function next_phases(uint256 num) public {
        vm.roll(block.number + num * PHASE_BLOCKS);
    }

    function jump_second_half_min() public {
        vm.roll(block.number + SECOND_HALF_MIN_BLOCKS);
    }

    // ============ Launch Helpers ============

    function launch_contribute(FlowUserParams memory p) public {
        ILOVE20Token token = ILOVE20Token(p.tokenAddress);
        IERC20 parentToken = IERC20(token.parentTokenAddress());

        uint256 contributeAmount = p.launch.contributeParentTokenAmount > 0
            ? p.launch.contributeParentTokenAmount
            : (p.launch.contributeParentTokenAmountPercent *
                parentToken.balanceOf(p.userAddress)) / 100;

        vm.startPrank(p.userAddress);
        parentToken.approve(address(launchContract), contributeAmount);
        launchContract.contribute(
            p.tokenAddress,
            contributeAmount,
            p.launch.contributeToAddress
        );
        vm.stopPrank();
    }

    function launch_skip_claim_delay() public {
        vm.roll(block.number + WITHDRAW_WAITING_BLOCKS + 1);
    }

    function launch_claim(FlowUserParams memory p) public {
        vm.startPrank(p.userAddress);
        launchContract.claim(p.tokenAddress);
        vm.stopPrank();
    }

    // ============ Stake Helpers ============

    function stake_liquidity(
        FlowUserParams memory p
    ) public returns (uint256 govVotes) {
        ILOVE20Token token = ILOVE20Token(p.tokenAddress);
        IERC20 parentToken = IERC20(token.parentTokenAddress());

        uint256 parentTokenAmount = (p.stake.parentTokenAmountForLpPercent *
            parentToken.balanceOf(p.userAddress)) / 100;
        uint256 tokenAmount = (p.stake.tokenAmountForLpPercent *
            token.balanceOf(p.userAddress)) / 100;

        vm.startPrank(p.userAddress);
        parentToken.approve(address(stakeContract), parentTokenAmount);
        IERC20(p.tokenAddress).approve(address(stakeContract), tokenAmount);

        uint256 slAmountAdded;
        (govVotes, slAmountAdded) = stakeContract.stakeLiquidity(
            p.tokenAddress,
            tokenAmount,
            parentTokenAmount,
            p.stake.promisedWaitingPhases,
            p.userAddress
        );
        vm.stopPrank();

        return govVotes;
    }

    function stake_token(
        FlowUserParams memory p
    ) public returns (uint256 govVotesAdded) {
        ILOVE20Token token = ILOVE20Token(p.tokenAddress);
        uint256 tokenAmount = (p.stake.tokenAmountPercent *
            token.balanceOf(p.userAddress)) / 100;

        vm.startPrank(p.userAddress);
        IERC20(p.tokenAddress).approve(address(stakeContract), tokenAmount);
        govVotesAdded = stakeContract.stakeToken(
            p.tokenAddress,
            tokenAmount,
            p.stake.promisedWaitingPhases,
            p.userAddress
        );
        vm.stopPrank();

        return govVotesAdded;
    }

    // ============ Submit Helpers ============

    function submit_new_action(
        FlowUserParams memory p
    ) public returns (uint256 actionId) {
        ActionBody memory actionBody = _buildActionBody(p);
        actionId = _doSubmit(p.userAddress, p.tokenAddress, actionBody);
    }

    function _buildActionBody(
        FlowUserParams memory p
    ) internal pure returns (ActionBody memory actionBody) {
        actionBody.minStake = p.submit.minStake;
        actionBody.maxRandomAccounts = p.submit.maxRandomAccounts;
        actionBody.whiteListAddress = p.submit.whiteListAddress;
        actionBody.title = p.submit.title;
        actionBody.verificationRule = p.submit.verificationRule;
        actionBody.verificationKeys = p.submit.verificationKeys;
        actionBody.verificationInfoGuides = p.submit.verificationInfoGuides;
    }

    function _doSubmit(
        address userAddress,
        address tokenAddress,
        ActionBody memory actionBody
    ) internal returns (uint256 actionId) {
        vm.startPrank(userAddress);
        actionId = submitContract.submitNewAction(tokenAddress, actionBody);
        vm.stopPrank();
    }

    // ============ Vote Helpers ============

    function vote(FlowUserParams memory p) public {
        uint256 maxVotesNum = voteContract.maxVotesNum(
            p.tokenAddress,
            p.userAddress
        );
        uint256 userVotedNum = p.vote.voteNum > 0
            ? p.vote.voteNum
            : (maxVotesNum * p.vote.votePercent) / 100;

        uint256[] memory actionIds = new uint256[](1);
        actionIds[0] = p.actionId;
        uint256[] memory votes = new uint256[](1);
        votes[0] = userVotedNum;

        vm.startPrank(p.userAddress);
        voteContract.vote(p.tokenAddress, actionIds, votes);
        vm.stopPrank();
    }

    // ============ Group Action Helpers ============

    function group_action_create(
        GroupUserParams memory user
    ) public returns (address) {
        IERC20 token = IERC20(user.flow.tokenAddress);

        if (token.balanceOf(user.flow.userAddress) < DEFAULT_JOIN_AMOUNT) {
            forceMint(
                user.flow.tokenAddress,
                user.flow.userAddress,
                DEFAULT_JOIN_AMOUNT
            );
        }

        vm.startPrank(user.flow.userAddress);
        token.approve(address(groupActionFactory), DEFAULT_JOIN_AMOUNT);
        address extensionAddr = groupActionFactory.createExtension(
            user.flow.tokenAddress,
            address(groupManager),
            address(groupDistrust),
            user.flow.tokenAddress,
            DEFAULT_MIN_GOV_VOTE_RATIO_BPS,
            DEFAULT_GROUP_ACTIVATION_STAKE_AMOUNT,
            DEFAULT_MAX_JOIN_AMOUNT_MULTIPLIER
        );
        vm.stopPrank();

        user.groupActionAddress = extensionAddr;
        return extensionAddr;
    }

    function submit_group_action(
        GroupUserParams memory user
    ) public returns (uint256 actionId) {
        user.flow.submit.whiteListAddress = user.groupActionAddress;
        actionId = submit_new_action(user.flow);
        user.groupActionId = actionId;
        user.flow.actionId = actionId;
        return actionId;
    }

    function group_activate(GroupUserParams memory user) public {
        address tokenAddress = user.flow.tokenAddress;
        IERC20 token = IERC20(tokenAddress);

        if (token.balanceOf(user.flow.userAddress) < user.stakeAmount) {
            forceMint(tokenAddress, user.flow.userAddress, user.stakeAmount);
        }

        vm.startPrank(user.flow.userAddress, user.flow.userAddress);
        token.approve(address(groupManager), user.stakeAmount);
        groupManager.activateGroup(
            tokenAddress,
            user.groupActionId,
            user.groupId,
            user.groupDescription,
            user.maxCapacity,
            user.minJoinAmount,
            user.maxJoinAmount,
            0
        );
        vm.stopPrank();
    }

    function group_join(
        GroupUserParams memory member,
        GroupUserParams memory groupOwner
    ) public {
        address tokenAddress = member.flow.tokenAddress;
        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(
            groupOwner.groupActionAddress
        );
        IERC20 token = IERC20(tokenAddress);

        // Ensure we are not in the last blocks of the phase (LastBlocksOfPhaseCannotJoin check)
        uint256 currentRound = joinContract.currentRound();
        uint256 joinEndPhaseBlocks = joinContract.JOIN_END_PHASE_BLOCKS();
        if (
            joinContract.roundByBlockNumber(
                block.number + joinEndPhaseBlocks
            ) != currentRound
        ) {
            // Roll forward to ensure we're in a safe part of the next phase
            vm.roll(block.number + joinEndPhaseBlocks + 1);
        }

        if (token.balanceOf(member.flow.userAddress) < member.joinAmount) {
            forceMint(tokenAddress, member.flow.userAddress, member.joinAmount);
        }

        vm.startPrank(member.flow.userAddress);
        token.approve(address(groupAction), member.joinAmount);
        groupAction.join(
            groupOwner.groupId,
            member.joinAmount,
            new string[](0)
        );
        vm.stopPrank();
    }

    function group_submit_score(
        GroupUserParams memory groupOwner,
        uint256[] memory scores
    ) public {
        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(
            groupOwner.groupActionAddress
        );

        vm.prank(groupOwner.flow.userAddress);
        groupAction.submitOriginScore(groupOwner.groupId, 0, scores);
    }

    function group_exit(
        GroupUserParams memory member,
        GroupUserParams memory groupOwner
    ) public {
        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(
            groupOwner.groupActionAddress
        );

        vm.prank(member.flow.userAddress);
        groupAction.exit();
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
        IERC20 token = IERC20(user.flow.tokenAddress);

        if (token.balanceOf(user.flow.userAddress) < DEFAULT_JOIN_AMOUNT) {
            forceMint(
                user.flow.tokenAddress,
                user.flow.userAddress,
                DEFAULT_JOIN_AMOUNT
            );
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

    function submit_group_service_action(
        GroupUserParams memory user
    ) public returns (uint256 actionId) {
        user.flow.submit.whiteListAddress = user.groupServiceAddress;
        actionId = submit_new_action(user.flow);
        user.groupServiceActionId = actionId;
        return actionId;
    }

    function group_service_join(GroupUserParams memory groupOwner) public {
        LOVE20ExtensionGroupService groupService = LOVE20ExtensionGroupService(
            groupOwner.groupServiceAddress
        );

        vm.prank(groupOwner.flow.userAddress);
        groupService.join(new string[](0));
    }

    function group_service_set_recipients(
        GroupUserParams memory groupOwner
    ) public {
        LOVE20ExtensionGroupService groupService = LOVE20ExtensionGroupService(
            groupOwner.groupServiceAddress
        );

        vm.prank(groupOwner.flow.userAddress);
        groupService.setRecipients(
            groupOwner.recipients,
            groupOwner.basisPoints
        );
    }

    function group_distrust_vote(
        GroupUserParams memory voter,
        GroupUserParams memory target,
        uint256 amount,
        string memory reason
    ) public {
        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(
            target.groupActionAddress
        );

        vm.prank(voter.flow.userAddress, voter.flow.userAddress);
        groupAction.distrustVote(target.flow.userAddress, amount, reason);
    }

    // ============ Core Verify Helpers ============

    /// @notice Verify extension (give score to extension contract in core Verify)
    /// @dev Verifier must have voted for the action and calls LOVE20Verify.verify()
    function core_verify_extension(
        FlowUserParams memory verifier,
        address tokenAddress,
        uint256 actionId,
        address extensionAddress
    ) public {
        // Get random accounts from join contract
        address[] memory accounts = joinContract.prepareRandomAccountsIfNeeded(
            tokenAddress,
            actionId
        );

        // Build scores array - give full score to extension account
        uint256[] memory scores = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == extensionAddress) {
                scores[i] = 100;
            }
        }

        vm.prank(verifier.userAddress);
        verifyContract.verify(tokenAddress, actionId, 0, scores);
    }

    /// @notice Shorthand for group action verification
    function core_verify_extension(
        GroupUserParams memory verifier,
        address extensionAddress
    ) public {
        core_verify_extension(
            verifier.flow,
            verifier.flow.tokenAddress,
            verifier.groupActionId,
            extensionAddress
        );
    }

    // ============ Reward Claim Helpers ============

    /// @notice Claim reward for group action participant
    function group_action_claim_reward(
        GroupUserParams memory member,
        GroupUserParams memory groupOwner,
        uint256 round
    ) public returns (uint256 reward) {
        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(
            groupOwner.groupActionAddress
        );

        vm.prank(member.flow.userAddress);
        reward = groupAction.claimReward(round);
    }

    /// @notice Claim reward for group service provider
    function group_service_claim_reward(
        GroupUserParams memory groupOwner,
        uint256 round
    ) public returns (uint256 reward) {
        LOVE20ExtensionGroupService groupService = LOVE20ExtensionGroupService(
            groupOwner.groupServiceAddress
        );

        vm.prank(groupOwner.flow.userAddress);
        reward = groupService.claimReward(round);
    }

    // ============ View Helpers ============

    function getGroupManager() public view returns (LOVE20GroupManager) {
        return groupManager;
    }

    function getGroupDistrust() public view returns (LOVE20GroupDistrust) {
        return groupDistrust;
    }

    function getExtensionCenter() public view returns (LOVE20ExtensionCenter) {
        return extensionCenter;
    }

    function getGroup() public view returns (LOVE20Group) {
        return group;
    }
}
