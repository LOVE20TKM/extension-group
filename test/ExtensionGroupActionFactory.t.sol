// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {
    ExtensionGroupActionFactory
} from "../src/ExtensionGroupActionFactory.sol";
import {
    IGroupActionFactory
} from "../src/interface/IGroupActionFactory.sol";
import {ExtensionGroupAction} from "../src/ExtensionGroupAction.sol";
import {
    IGroupAction
} from "../src/interface/IGroupAction.sol";
import {GroupManager} from "../src/GroupManager.sol";
import {GroupJoin} from "../src/GroupJoin.sol";
import {GroupVerify} from "../src/GroupVerify.sol";
import {IGroupManager} from "../src/interface/IGroupManager.sol";
import {IGroupJoin} from "../src/interface/IGroupJoin.sol";
import {IGroupVerify} from "../src/interface/IGroupVerify.sol";
import {MockGroupToken} from "./mocks/MockGroupToken.sol";

/**
 * @title ExtensionGroupActionFactoryTest
 * @notice Test suite for ExtensionGroupActionFactory
 */
contract ExtensionGroupActionFactoryTest is BaseGroupTest {
    ExtensionGroupActionFactory public factory;
    GroupManager public newGroupManager;
    GroupJoin public newGroupJoin;
    GroupVerify public newGroupVerify;

    // Event declaration for testing
    event ExtensionCreate(
        address indexed extension,
        address indexed tokenAddress
    );

    function setUp() public {
        setUpBase();

        // Create new singleton instances for this test (not using BaseGroupTest's instances)
        // because ExtensionGroupActionFactory constructor will initialize them
        newGroupManager = new GroupManager();
        newGroupJoin = new GroupJoin();
        newGroupVerify = new GroupVerify();

        // Deploy Factory
        factory = new ExtensionGroupActionFactory(
            address(center),
            address(newGroupManager),
            address(newGroupJoin),
            address(newGroupVerify),
            address(group)
        );

        // Initialize singletons after factory is fully constructed
        IGroupManager(address(newGroupManager)).initialize(address(factory));
        IGroupJoin(address(newGroupJoin)).initialize(address(factory));
        IGroupVerify(address(newGroupVerify)).initialize(address(factory));
    }

    // ============ Constructor Tests ============

    function test_Constructor_StoresCenter() public view {
        assertEq(factory.CENTER_ADDRESS(), address(center));
    }

    function test_Constructor_StoresGroupManagerAddress() public view {
        assertEq(factory.GROUP_MANAGER_ADDRESS(), address(newGroupManager));
    }

    function test_Constructor_StoresGroupJoinAddress() public view {
        assertEq(factory.GROUP_JOIN_ADDRESS(), address(newGroupJoin));
    }

    function test_Constructor_StoresGroupVerifyAddress() public view {
        assertEq(factory.GROUP_VERIFY_ADDRESS(), address(newGroupVerify));
    }

    function test_Constructor_InitializesGroupJoin() public view {
        assertEq(newGroupJoin.FACTORY_ADDRESS(), address(factory));
    }

    function test_Constructor_InitializesGroupVerify() public view {
        assertEq(newGroupVerify.FACTORY_ADDRESS(), address(factory));
    }

    // ============ CreateExtension Tests ============

    function test_CreateExtension_Success() public {
        // Prepare tokens for registration
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        assertTrue(extension != address(0));
        assertTrue(factory.exists(extension));
    }

    function test_CreateExtension_RegistersExtension() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        assertEq(factory.extensionsCount(), 1);
        assertEq(factory.extensionsAtIndex(0), extension);

        address[] memory allExtensions = factory.extensions();
        assertEq(allExtensions.length, 1);
        assertEq(allExtensions[0], extension);
    }

    function test_CreateExtension_TransfersInitialTokens() public {
        uint256 balanceBefore = token.balanceOf(address(this));
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        uint256 balanceAfter = token.balanceOf(address(this));
        assertEq(balanceBefore - balanceAfter, 1e18);
        assertEq(token.balanceOf(extension), 1e18);
    }

    function test_CreateExtension_SetsCorrectFactory() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        ExtensionGroupAction groupAction = ExtensionGroupAction(extension);
        assertEq(groupAction.FACTORY_ADDRESS(), address(factory));
    }

    function test_CreateExtension_MultipleExtensions() public {
        // Create multiple tokens for multiple extensions
        // (each token can only have one GroupAction extension with actionId=0)
        MockGroupToken token2 = new MockGroupToken();
        MockGroupToken token3 = new MockGroupToken();

        token.approve(address(factory), 1e18);
        token2.mint(address(this), 1e18);
        token2.approve(address(factory), 1e18);
        token3.mint(address(this), 1e18);
        token3.approve(address(factory), 1e18);

        address ext1 = factory.createExtension(
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        address ext2 = factory.createExtension(
            address(token2),
            address(token2), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        address ext3 = factory.createExtension(
            address(token3),
            address(token3), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        assertEq(factory.extensionsCount(), 3);
        assertTrue(factory.exists(ext1));
        assertTrue(factory.exists(ext2));
        assertTrue(factory.exists(ext3));
    }

    // ============ ExtensionParams Tests ============

    function test_ExtensionParams_ReturnsCorrectValues() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        ExtensionGroupAction ext = ExtensionGroupAction(extension);

        // Verify extension token address
        assertEq(ext.TOKEN_ADDRESS(), address(token));

        // Verify Factory addresses
        assertEq(factory.GROUP_MANAGER_ADDRESS(), address(newGroupManager));

        // Verify config is set in GroupManager (need to register extension first and get actionId)
        // For now, just verify the extension exists
        assertTrue(factory.exists(extension));
    }

    // ============ Exists Tests ============

    function test_Exists_ReturnsTrueForCreated() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        assertTrue(factory.exists(extension));
    }

    function test_Exists_ReturnsFalseForNonExistent() public view {
        assertFalse(factory.exists(address(0x123)));
        assertFalse(factory.exists(address(0)));
    }

    // ============ ExtensionCreate Event Tests ============

    function test_CreateExtension_EmitsExtensionCreate() public {
        token.approve(address(factory), 1e18);

        // Calculate expected extension address
        uint256 nonce = vm.getNonce(address(factory));
        address expectedExtension = vm.computeCreateAddress(
            address(factory),
            nonce
        );

        vm.expectEmit(true, true, false, false);
        emit ExtensionCreate(expectedExtension, address(token));

        address extension = factory.createExtension(
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        assertEq(extension, expectedExtension);
    }

    // ============ VotedGroupActions Tests ============

    function test_VotedGroupActions_Empty() public view {
        uint256 emptyRound = 999;
        (uint256[] memory aids, address[] memory exts) = factory
            .votedGroupActions(address(token), emptyRound);

        assertEq(exts.length, 0);
        assertEq(aids.length, 0);
    }

    function test_VotedGroupActions_SingleValid() public {
        token.approve(address(factory), 1e18);
        address extension = factory.createExtension(
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        uint256 actionId = 0;
        prepareExtensionInit(extension, address(token), actionId);

        uint256 round = join.currentRound();
        (uint256[] memory aids, address[] memory exts) = factory
            .votedGroupActions(address(token), round);

        assertEq(exts.length, 1);
        assertEq(aids.length, 1);
        assertEq(exts[0], extension);
        assertEq(aids[0], actionId);
    }

    function test_VotedGroupActions_MultipleValid() public {
        token.approve(address(factory), 2e18);
        address ext1 = factory.createExtension(
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        MockGroupToken token2 = new MockGroupToken();
        token2.mint(address(this), 1e18);
        token2.approve(address(factory), 1e18);
        address ext2 = factory.createExtension(
            address(token2),
            address(token2),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        uint256 actionId1 = 0;
        uint256 actionId2 = 1;
        prepareExtensionInit(ext1, address(token), actionId1);
        prepareExtensionInit(ext2, address(token2), actionId2);

        uint256 round = join.currentRound();
        (uint256[] memory aids, address[] memory exts) = factory
            .votedGroupActions(address(token), round);

        assertEq(exts.length, 1);
        assertEq(aids.length, 1);
        assertEq(exts[0], ext1);
        assertEq(aids[0], actionId1);
    }

    function test_VotedGroupActions_FiltersInvalidExtension() public {
        token.approve(address(factory), 1e18);
        address extension = factory.createExtension(
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        uint256 actionId1 = 0;
        prepareExtensionInit(extension, address(token), actionId1);

        // Add an actionId with extension not registered in factory
        uint256 invalidActionId = 200;
        address invalidExtension = address(token); // Not registered in Factory
        submit.setActionInfo(address(token), invalidActionId, invalidExtension);
        vote.setVotedActionIds(
            address(token),
            join.currentRound(),
            invalidActionId
        );

        uint256 round = join.currentRound();
        (uint256[] memory aids, address[] memory exts) = factory
            .votedGroupActions(address(token), round);

        // Should only return the valid one (registered in Factory)
        assertEq(exts.length, 1);
        assertEq(aids.length, 1);
        assertEq(exts[0], extension);
        assertEq(aids[0], actionId1);
    }

    function test_VotedGroupActions_FiltersZeroExtension() public {
        token.approve(address(factory), 1e18);
        address extension = factory.createExtension(
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        uint256 actionId1 = 0;
        prepareExtensionInit(extension, address(token), actionId1);

        // Add an actionId with zero extension address
        uint256 zeroActionId = 300;
        submit.setActionInfo(address(token), zeroActionId, address(0));
        vote.setVotedActionIds(
            address(token),
            join.currentRound(),
            zeroActionId
        );

        uint256 round = join.currentRound();
        (uint256[] memory aids, address[] memory exts) = factory
            .votedGroupActions(address(token), round);

        // Should only return the valid one (non-zero extension registered in Factory)
        assertEq(exts.length, 1);
        assertEq(aids.length, 1);
        assertEq(exts[0], extension);
        assertEq(aids[0], actionId1);
    }

    function test_VotedGroupActions_WorksBeforeCenterRegistration() public {
        // Test that votedGroupActions works even when action is not registered in Center
        // It gets extension from submit.actionInfo.whiteListAddress
        token.approve(address(factory), 1e18);
        address extension = factory.createExtension(
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        // Set actionInfo with whiteListAddress but don't register in Center
        uint256 actionId = 500;
        submit.setActionInfo(address(token), actionId, extension);
        vote.setVotedActionIds(address(token), join.currentRound(), actionId);

        uint256 round = join.currentRound();
        (uint256[] memory aids, address[] memory exts) = factory
            .votedGroupActions(address(token), round);

        // Should find the extension even though it's not registered in Center
        assertEq(exts.length, 1);
        assertEq(aids.length, 1);
        assertEq(exts[0], extension);
        assertEq(aids[0], actionId);
    }
}
