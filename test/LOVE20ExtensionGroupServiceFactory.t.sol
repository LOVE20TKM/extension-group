// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {
    LOVE20ExtensionGroupServiceFactory
} from "../src/LOVE20ExtensionGroupServiceFactory.sol";
import {ILOVE20ExtensionGroupServiceFactory} from "../src/interface/ILOVE20ExtensionGroupServiceFactory.sol";
import {
    LOVE20ExtensionGroupService
} from "../src/LOVE20ExtensionGroupService.sol";
import {
    LOVE20ExtensionGroupActionFactory
} from "../src/LOVE20ExtensionGroupActionFactory.sol";
import {LOVE20GroupDistrust} from "../src/LOVE20GroupDistrust.sol";
import {ILOVE20GroupManager} from "../src/interface/ILOVE20GroupManager.sol";

/**
 * @title LOVE20ExtensionGroupServiceFactoryTest
 * @notice Test suite for LOVE20ExtensionGroupServiceFactory
 */
contract LOVE20ExtensionGroupServiceFactoryTest is BaseGroupTest {
    LOVE20ExtensionGroupServiceFactory public factory;
    LOVE20ExtensionGroupActionFactory public actionFactory;
    LOVE20GroupDistrust public groupDistrust;

    uint256 constant MAX_RECIPIENTS = 10;

    // Event declaration for testing
    event ExtensionCreate(
        address indexed extension,
        address indexed tokenAddress,
        address groupActionTokenAddress,
        address groupActionFactoryAddress,
        uint256 maxRecipients
    );

    function setUp() public {
        setUpBase();

        // Deploy GroupDistrust singleton
        groupDistrust = new LOVE20GroupDistrust(
            address(center),
            address(verify),
            address(group)
        );

        // Deploy GroupAction factory
        actionFactory = new LOVE20ExtensionGroupActionFactory(address(center));

        // Deploy GroupService factory
        factory = new LOVE20ExtensionGroupServiceFactory(address(center));
    }

    // ============ Constructor Tests ============

    function test_Constructor_StoresCenter() public view {
        assertEq(factory.center(), address(center));
    }

    // ============ CreateExtension Tests ============

    function test_CreateExtension_Success() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(token),
            address(actionFactory),
            MAX_RECIPIENTS
        );

        assertTrue(extension != address(0));
        assertTrue(factory.exists(extension));
    }

    function test_CreateExtension_RegistersExtension() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(token),
            address(actionFactory),
            MAX_RECIPIENTS
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
            address(actionFactory),
            MAX_RECIPIENTS
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
            address(actionFactory),
            MAX_RECIPIENTS
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
            address(token),
            address(actionFactory),
            MAX_RECIPIENTS
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

        address ext1 = factory.createExtension(
            address(token),
            address(token),
            address(actionFactory),
            MAX_RECIPIENTS
        );

        address ext2 = factory.createExtension(
            address(token),
            address(token),
            address(actionFactory),
            5 // different max recipients
        );

        address ext3 = factory.createExtension(
            address(token),
            address(token),
            address(actionFactory),
            20
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
            address(actionFactory),
            MAX_RECIPIENTS
        );

        (
            address tokenAddress,
            address groupActionTokenAddr,
            address groupActionFactoryAddr,
            uint256 maxRecipients
        ) = factory.extensionParams(extension);

        assertEq(tokenAddress, address(token));
        assertEq(groupActionTokenAddr, address(token));
        assertEq(groupActionFactoryAddr, address(actionFactory));
        assertEq(maxRecipients, MAX_RECIPIENTS);
    }

    function test_ExtensionParams_ZeroForNonExistent() public view {
        (
            address tokenAddress,
            address groupActionTokenAddr,
            address groupActionFactoryAddr,
            uint256 maxRecipients
        ) = factory.extensionParams(address(0x123));

        assertEq(tokenAddress, address(0));
        assertEq(groupActionTokenAddr, address(0));
        assertEq(groupActionFactoryAddr, address(0));
        assertEq(maxRecipients, 0);
    }

    // ============ Exists Tests ============

    function test_Exists_ReturnsTrueForCreated() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(token),
            address(actionFactory),
            MAX_RECIPIENTS
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
        emit ExtensionCreate({
            extension: expectedExtension,
            tokenAddress: address(token),
            groupActionTokenAddress: address(token),
            groupActionFactoryAddress: address(actionFactory),
            maxRecipients: MAX_RECIPIENTS
        });

        address extension = factory.createExtension(
            address(token),
            address(token),
            address(actionFactory),
            MAX_RECIPIENTS
        );

        assertEq(extension, expectedExtension);
    }
}
