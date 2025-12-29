// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {
    LOVE20ExtensionGroupServiceFactory
} from "../src/LOVE20ExtensionGroupServiceFactory.sol";
import {
    ILOVE20ExtensionGroupServiceFactory
} from "../src/interface/ILOVE20ExtensionGroupServiceFactory.sol";
import {
    LOVE20ExtensionGroupService
} from "../src/LOVE20ExtensionGroupService.sol";
import {
    ILOVE20ExtensionGroupService
} from "../src/interface/ILOVE20ExtensionGroupService.sol";
import {
    LOVE20ExtensionGroupActionFactory
} from "../src/LOVE20ExtensionGroupActionFactory.sol";
import {GroupManager} from "../src/GroupManager.sol";
import {GroupJoin} from "../src/GroupJoin.sol";
import {GroupVerify} from "../src/GroupVerify.sol";
import {IGroupManager} from "../src/interface/IGroupManager.sol";
import {IGroupJoin} from "../src/interface/IGroupJoin.sol";
import {IGroupVerify} from "../src/interface/IGroupVerify.sol";

/**
 * @title LOVE20ExtensionGroupServiceFactoryTest
 * @notice Test suite for LOVE20ExtensionGroupServiceFactory
 */
contract LOVE20ExtensionGroupServiceFactoryTest is BaseGroupTest {
    LOVE20ExtensionGroupServiceFactory public factory;
    LOVE20ExtensionGroupActionFactory public actionFactory;

    uint256 constant MAX_RECIPIENTS = 100;

    // Event declaration for testing
    event ExtensionCreate(
        address indexed extension,
        address indexed tokenAddress
    );

    function setUp() public {
        setUpBase();

        // Create new singleton instances for this test (not using BaseGroupTest's instances)
        // because LOVE20ExtensionGroupActionFactory constructor will initialize them
        GroupManager newGroupManager = new GroupManager();
        GroupJoin newGroupJoin = new GroupJoin();
        GroupVerify newGroupVerify = new GroupVerify();

        // Deploy GroupAction factory
        actionFactory = new LOVE20ExtensionGroupActionFactory(
            address(center),
            address(newGroupManager),
            address(newGroupJoin),
            address(newGroupVerify),
            address(group)
        );
        // Initialize singletons after factory is fully constructed
        IGroupManager(address(newGroupManager)).initialize(
            address(actionFactory)
        );
        IGroupJoin(address(newGroupJoin)).initialize(address(actionFactory));
        IGroupVerify(address(newGroupVerify)).initialize(
            address(actionFactory)
        );

        // Deploy GroupService factory
        factory = new LOVE20ExtensionGroupServiceFactory(
            address(actionFactory)
        );
    }

    // ============ Constructor Tests ============

    function test_Constructor_StoresGroupActionFactory() public view {
        assertEq(
            factory.GROUP_ACTION_FACTORY_ADDRESS(),
            address(actionFactory)
        );
        assertEq(factory.center(), address(center));
    }

    // ============ CreateExtension Tests ============

    function test_CreateExtension_Success() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(token)
        );

        assertTrue(extension != address(0));
        assertTrue(factory.exists(extension));
    }

    function test_CreateExtension_RegistersExtension() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(token)
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
            address(token)
        );

        uint256 balanceAfter = token.balanceOf(address(this));
        assertEq(balanceBefore - balanceAfter, 1e18);
        assertEq(token.balanceOf(extension), 1e18);
    }

    function test_CreateExtension_SetsCorrectFactory() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(token)
        );

        LOVE20ExtensionGroupService groupService = LOVE20ExtensionGroupService(
            extension
        );
        assertEq(groupService.factory(), address(factory));
    }

    function test_CreateExtension_SetsCorrectGroupActionFactoryAddress()
        public
    {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(token)
        );

        LOVE20ExtensionGroupService groupService = LOVE20ExtensionGroupService(
            extension
        );
        assertEq(groupService.GROUP_ACTION_TOKEN_ADDRESS(), address(token));
        assertEq(
            groupService.GROUP_ACTION_FACTORY_ADDRESS(),
            address(actionFactory)
        );
    }

    function test_CreateExtension_MultipleExtensions() public {
        token.approve(address(factory), 3e18);

        address ext1 = factory.createExtension(address(token), address(token));

        address ext2 = factory.createExtension(address(token), address(token));

        address ext3 = factory.createExtension(address(token), address(token));

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
            address(token)
        );

        LOVE20ExtensionGroupService ext = LOVE20ExtensionGroupService(
            extension
        );

        // All parameters are public immutable, can be accessed directly
        assertEq(ext.tokenAddress(), address(token));
        assertEq(ext.GROUP_ACTION_TOKEN_ADDRESS(), address(token));
        assertEq(ext.GROUP_ACTION_FACTORY_ADDRESS(), address(actionFactory));
        assertEq(ext.DEFAULT_MAX_RECIPIENTS(), MAX_RECIPIENTS);
    }

    // ============ Exists Tests ============

    function test_Exists_ReturnsTrueForCreated() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(token)
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
            address(token)
        );

        assertEq(extension, expectedExtension);
    }
}
