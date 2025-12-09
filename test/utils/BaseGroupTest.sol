// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test, console} from "forge-std/Test.sol";

// Import local mock contracts
import {MockExtensionCenter} from "../mocks/MockExtensionCenter.sol";

// Import mock contracts from extension
import {MockERC20} from "@extension/test/mocks/MockERC20.sol";
import {MockStake} from "@extension/test/mocks/MockStake.sol";
import {MockJoin} from "@extension/test/mocks/MockJoin.sol";
import {MockMint} from "@extension/test/mocks/MockMint.sol";
import {MockSubmit} from "@extension/test/mocks/MockSubmit.sol";
import {MockLaunch} from "@extension/test/mocks/MockLaunch.sol";
import {MockVote} from "@extension/test/mocks/MockVote.sol";
import {MockRandom} from "@extension/test/mocks/MockRandom.sol";
import {
    MockUniswapV2Factory
} from "@extension/test/mocks/MockUniswapV2Factory.sol";
import {
    MockExtensionFactory
} from "@extension/test/mocks/MockExtensionFactory.sol";

// Import local mock contracts
import {MockGroup} from "../mocks/MockGroup.sol";
import {MockGroupToken} from "../mocks/MockGroupToken.sol";
import {MockVerifyExtended} from "../mocks/MockVerifyExtended.sol";

// Import GroupManager
import {LOVE20GroupManager} from "../../src/LOVE20GroupManager.sol";
import {ILOVE20GroupManager} from "../../src/interface/ILOVE20GroupManager.sol";

/**
 * @title BaseGroupTest
 * @notice Base test utility for group extension tests
 */
abstract contract BaseGroupTest is Test {
    // ============ Core Contracts ============

    MockExtensionCenter public center;
    MockGroupToken public token;
    MockGroup public group;
    MockUniswapV2Factory public uniswapFactory;
    MockExtensionFactory public mockFactory;

    // ============ GroupManager (singleton) ============

    LOVE20GroupManager public groupManager;

    // ============ Mock Contracts ============

    MockStake public stake;
    MockJoin public join;
    MockVerifyExtended public verify;
    MockMint public mint;
    MockSubmit public submit;
    MockLaunch public launch;
    MockVote public vote;
    MockRandom public random;

    // ============ Test Users ============

    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);
    address public user4 = address(0x4);
    address public groupOwner1 = address(0x10);
    address public groupOwner2 = address(0x20);
    address public deployer = address(this);

    // ============ Constants ============

    uint256 constant ACTION_ID = 0; // Config is set at construction time with actionId=0
    uint256 constant WAITING_BLOCKS = 100;

    // Group configuration constants
    uint256 constant MIN_GOV_VOTE_RATIO_BPS = 100; // 1%
    uint256 constant CAPACITY_MULTIPLIER = 10;
    uint256 constant STAKING_MULTIPLIER = 100;
    uint256 constant MAX_JOIN_AMOUNT_MULTIPLIER = 100;
    uint256 constant MIN_JOIN_AMOUNT = 1e18;
    uint256 constant DEFAULT_STAKE_AMOUNT = 10000e18; // Min stake based on total supply

    // ============ Setup Functions ============

    function setUpBase() internal virtual {
        // Deploy mock contracts
        token = new MockGroupToken();
        group = new MockGroup();
        stake = new MockStake();
        join = new MockJoin();
        verify = new MockVerifyExtended();
        mint = new MockMint();
        submit = new MockSubmit();
        launch = new MockLaunch();
        vote = new MockVote();
        random = new MockRandom();
        uniswapFactory = new MockUniswapV2Factory();

        // Deploy extension center (using MockExtensionCenter for testing)
        center = new MockExtensionCenter(
            address(uniswapFactory),
            address(launch),
            address(stake),
            address(submit),
            address(vote),
            address(join),
            address(verify),
            address(mint),
            address(random)
        );

        // Deploy mock factory
        mockFactory = new MockExtensionFactory(address(center));

        // Deploy GroupManager singleton
        groupManager = new LOVE20GroupManager(
            address(center),
            address(group),
            address(stake),
            address(join)
        );

        // Setup initial token supply
        token.mint(address(this), 1_000_000e18);

        // Setup initial governance votes (total) - larger for testing
        stake.setGovVotesNum(address(token), 100_000e18);

        // Initialize current round
        verify.setCurrentRound(1);
        join.setCurrentRound(1);
    }

    /**
     * @notice Create default GroupConfig for testing
     */
    function createDefaultGroupConfig()
        internal
        view
        returns (ILOVE20GroupManager.GroupConfig memory)
    {
        return
            ILOVE20GroupManager.GroupConfig({
                stakeTokenAddress: address(token),
                minGovVoteRatioBps: MIN_GOV_VOTE_RATIO_BPS,
                capacityMultiplier: CAPACITY_MULTIPLIER,
                stakingMultiplier: STAKING_MULTIPLIER,
                maxJoinAmountMultiplier: MAX_JOIN_AMOUNT_MULTIPLIER,
                minJoinAmount: MIN_JOIN_AMOUNT
            });
    }

    // ============ Helper Functions ============

    /**
     * @notice Setup a group owner with NFT and governance votes
     */
    function setupGroupOwner(
        address owner,
        uint256 govVotes,
        string memory groupName
    ) internal returns (uint256 groupId) {
        // Mint group NFT
        groupId = group.mint(owner, groupName);

        // Setup governance votes
        stake.setValidGovVotes(address(token), owner, govVotes);
    }

    /**
     * @notice Setup user with tokens and approval
     */
    function setupUser(address user, uint256 amount, address spender) internal {
        token.mint(user, amount);
        vm.prank(user);
        token.approve(spender, type(uint256).max);
    }

    /**
     * @notice Register factory to center
     */
    function registerFactory(address tokenAddr, address factory) internal {
        submit.setCanSubmit(tokenAddr, address(this), true);
        center.addFactory(tokenAddr, factory);
    }

    /**
     * @notice Prepare extension initialization and register to center
     */
    function prepareExtensionInit(
        address extensionAddress,
        address tokenAddr,
        uint256 actionId
    ) internal {
        submit.setActionInfo(tokenAddr, actionId, extensionAddress);
        vote.setVotedActionIds(tokenAddr, join.currentRound(), actionId);
        token.mint(extensionAddress, 1e18);
        // Register extension to center for GroupManager lookup
        center.setExtension(tokenAddr, actionId, extensionAddress);
        // Mock center.registerExtension() to always succeed (called by _autoInitialize)
        vm.mockCall(
            address(center),
            abi.encodeWithSignature("registerExtension()"),
            abi.encode()
        );
    }

    /**
     * @notice Advance to next round
     */
    function advanceRound() internal {
        uint256 newRound = verify.currentRound() + 1;
        verify.setCurrentRound(newRound);
        join.setCurrentRound(newRound);
    }

    /**
     * @notice Setup verify votes for distrust testing
     */
    function setupVerifyVotes(
        address voter,
        uint256 actionId,
        address extensionAddress,
        uint256 amount
    ) internal {
        uint256 round = verify.currentRound();
        verify.setScoreByVerifierByActionIdByAccount(
            address(token),
            round,
            voter,
            actionId,
            extensionAddress,
            amount
        );
        // Also update the total
        uint256 currentTotal = getVerifyVotesTotal(actionId, extensionAddress);
        verify.setScoreByActionIdByAccount(
            address(token),
            round,
            actionId,
            extensionAddress,
            currentTotal + amount
        );
    }

    function getVerifyVotesTotal(
        uint256 actionId,
        address extensionAddress
    ) internal view returns (uint256) {
        return
            verify.scoreByActionIdByAccount(
                address(token),
                verify.currentRound(),
                actionId,
                extensionAddress
            );
    }

    // ============ Array Assertion Helpers ============

    function assertArrayEq(
        address[] memory actual,
        address[] memory expected,
        string memory message
    ) internal pure {
        assertEq(
            actual.length,
            expected.length,
            string.concat(message, ": length mismatch")
        );
        for (uint256 i = 0; i < actual.length; i++) {
            assertEq(
                actual[i],
                expected[i],
                string.concat(
                    message,
                    ": element mismatch at index ",
                    vm.toString(i)
                )
            );
        }
    }

    function assertArrayEq(
        uint256[] memory actual,
        uint256[] memory expected,
        string memory message
    ) internal pure {
        assertEq(
            actual.length,
            expected.length,
            string.concat(message, ": length mismatch")
        );
        for (uint256 i = 0; i < actual.length; i++) {
            assertEq(
                actual[i],
                expected[i],
                string.concat(
                    message,
                    ": element mismatch at index ",
                    vm.toString(i)
                )
            );
        }
    }
}
