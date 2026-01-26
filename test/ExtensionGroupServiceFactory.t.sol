// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {
    ExtensionGroupServiceFactory
} from "../src/ExtensionGroupServiceFactory.sol";
import {IGroupServiceFactory} from "../src/interface/IGroupServiceFactory.sol";
import {ExtensionGroupService} from "../src/ExtensionGroupService.sol";
import {IGroupService} from "../src/interface/IGroupService.sol";
import {
    ExtensionGroupActionFactory
} from "../src/ExtensionGroupActionFactory.sol";
import {GroupManager} from "../src/GroupManager.sol";
import {GroupJoin} from "../src/GroupJoin.sol";
import {GroupVerify} from "../src/GroupVerify.sol";
import {IGroupManager} from "../src/interface/IGroupManager.sol";
import {IGroupJoin} from "../src/interface/IGroupJoin.sol";
import {IGroupVerify} from "../src/interface/IGroupVerify.sol";
import {IGroupServiceFactoryErrors} from "../src/interface/IGroupServiceFactory.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {MockGroupToken} from "./mocks/MockGroupToken.sol";

/**
 * @title MockLOVE20Token
 * @notice Mock token that implements ILOVE20Token for testing
 */
contract MockLOVE20Token {
    address public immutable parentTokenAddress;

    constructor(address parent_) {
        parentTokenAddress = parent_;
    }
}

/**
 * @title ExtensionGroupServiceFactoryTest
 * @notice Test suite for ExtensionGroupServiceFactory
 */
contract ExtensionGroupServiceFactoryTest is BaseGroupTest {
    ExtensionGroupServiceFactory public factory;
    ExtensionGroupActionFactory public actionFactory;

    uint256 constant MAX_RECIPIENTS = 10;

    // Event declaration for testing
    event CreateExtension(
        address indexed extension,
        address indexed tokenAddress
    );

    function setUp() public {
        setUpBase();

        // Create new singleton instances for this test (not using BaseGroupTest's instances)
        // because ExtensionGroupActionFactory constructor will initialize them
        GroupManager newGroupManager = new GroupManager();
        GroupJoin newGroupJoin = new GroupJoin();
        GroupVerify newGroupVerify = new GroupVerify();

        // Deploy GroupAction factory
        actionFactory = new ExtensionGroupActionFactory(
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
        factory = new ExtensionGroupServiceFactory(address(actionFactory));
    }

    // ============ Constructor Tests ============

    function test_Constructor_StoresGroupActionFactory() public view {
        assertEq(
            factory.GROUP_ACTION_FACTORY_ADDRESS(),
            address(actionFactory)
        );
        assertEq(factory.CENTER_ADDRESS(), address(center));
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

        ExtensionGroupService groupService = ExtensionGroupService(extension);
        assertEq(groupService.FACTORY_ADDRESS(), address(factory));
    }

    function test_CreateExtension_SetsCorrectGroupActionFactoryAddress()
        public
    {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(token)
        );

        ExtensionGroupService groupService = ExtensionGroupService(extension);
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

        ExtensionGroupService ext = ExtensionGroupService(extension);

        // All parameters are public immutable, can be accessed directly
        assertEq(ext.TOKEN_ADDRESS(), address(token));
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

    // ============ CreateExtension Event Tests ============

    function test_CreateExtension_EmitsCreateExtension() public {
        token.approve(address(factory), 1e18);

        // Calculate expected extension address
        uint256 nonce = vm.getNonce(address(factory));
        address expectedExtension = vm.computeCreateAddress(
            address(factory),
            nonce
        );

        vm.expectEmit(true, true, false, false);
        emit CreateExtension(expectedExtension, address(token));

        address extension = factory.createExtension(
            address(token),
            address(token)
        );

        assertEq(extension, expectedExtension);
    }

    // ============ GroupActionTokenAddress Validation Tests ============

    function test_CreateExtension_InvalidGroupActionToken_NotLOVE20Token()
        public
    {
        token.approve(address(factory), 1e18);

        // Use a random address that's not a LOVE20Token
        address invalidToken = address(0x123);
        launch.setLOVE20Token(invalidToken, false);

        vm.expectRevert(IGroupServiceFactoryErrors.InvalidGroupActionTokenAddress.selector);
        factory.createExtension(address(token), invalidToken);
    }

    function test_CreateExtension_InvalidGroupActionToken_WrongParent() public {
        token.approve(address(factory), 1e18);

        // Create a child token with wrong parent
        MockGroupToken otherParent = new MockGroupToken();
        launch.setLOVE20Token(address(otherParent), true);
        MockLOVE20Token childToken = new MockLOVE20Token(address(otherParent));
        launch.setLOVE20Token(address(childToken), true);

        vm.expectRevert(IGroupServiceFactoryErrors.InvalidGroupActionTokenAddress.selector);
        factory.createExtension(address(token), address(childToken));
    }

    function test_CreateExtension_ValidGroupActionToken_SameAsTokenAddress()
        public
    {
        token.approve(address(factory), 1e18);

        // Should succeed when groupActionTokenAddress equals tokenAddress
        address extension = factory.createExtension(
            address(token),
            address(token)
        );

        assertTrue(extension != address(0));
        assertTrue(factory.exists(extension));
    }

    function test_CreateExtension_ValidGroupActionToken_ValidChildToken()
        public
    {
        token.approve(address(factory), 1e18);

        // Create a valid child token with correct parent
        MockLOVE20Token childToken = new MockLOVE20Token(address(token));
        launch.setLOVE20Token(address(childToken), true);

        // Should succeed when groupActionTokenAddress is a valid child token
        address extension = factory.createExtension(
            address(token),
            address(childToken)
        );

        assertTrue(extension != address(0));
        assertTrue(factory.exists(extension));

        ExtensionGroupService groupService = ExtensionGroupService(extension);
        assertEq(groupService.GROUP_ACTION_TOKEN_ADDRESS(), address(childToken));
    }
}
