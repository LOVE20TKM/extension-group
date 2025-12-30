// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {
    ExtensionGroupActionFactory
} from "../src/ExtensionGroupActionFactory.sol";
import {
    IExtensionGroupActionFactory
} from "../src/interface/IExtensionGroupActionFactory.sol";
import {
    ExtensionGroupAction
} from "../src/ExtensionGroupAction.sol";
import {
    IExtensionGroupAction
} from "../src/interface/IExtensionGroupAction.sol";
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
        assertEq(factory.center(), address(center));
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
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        ExtensionGroupAction groupAction = ExtensionGroupAction(
            extension
        );
        assertEq(groupAction.factory(), address(factory));
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
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        address ext2 = factory.createExtension(
            address(token2),
            address(token2),
            address(token2), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        address ext3 = factory.createExtension(
            address(token3),
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
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        ExtensionGroupAction ext = ExtensionGroupAction(extension);

        // Verify extension token address
        assertEq(ext.tokenAddress(), address(token));

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
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        assertEq(extension, expectedExtension);
    }
}
