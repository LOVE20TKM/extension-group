// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {
    LOVE20ExtensionGroupServiceFactory
} from "../src/LOVE20ExtensionGroupServiceFactory.sol";
import {
    LOVE20ExtensionGroupService
} from "../src/LOVE20ExtensionGroupService.sol";
import {
    LOVE20ExtensionGroupActionFactory
} from "../src/LOVE20ExtensionGroupActionFactory.sol";

/**
 * @title LOVE20ExtensionGroupServiceFactoryTest
 * @notice Test suite for LOVE20ExtensionGroupServiceFactory
 */
contract LOVE20ExtensionGroupServiceFactoryTest is BaseGroupTest {
    LOVE20ExtensionGroupServiceFactory public factory;
    LOVE20ExtensionGroupActionFactory public actionFactory;
    address public groupActionAddress;

    uint256 constant MAX_RECIPIENTS = 10;

    function setUp() public {
        setUpBase();

        // Deploy GroupAction factory and create a GroupAction first
        actionFactory = new LOVE20ExtensionGroupActionFactory(address(center));
        token.approve(address(actionFactory), 1e18);

        groupActionAddress = actionFactory.createExtension(
            address(token),
            address(group),
            MIN_GOV_VOTE_RATIO_BPS,
            CAPACITY_MULTIPLIER,
            STAKING_MULTIPLIER,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            MIN_JOIN_AMOUNT
        );

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
            groupActionAddress,
            MAX_RECIPIENTS
        );

        assertTrue(extension != address(0));
        assertTrue(factory.exists(extension));
    }

    function test_CreateExtension_RegistersExtension() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            groupActionAddress,
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
            groupActionAddress,
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
            groupActionAddress,
            MAX_RECIPIENTS
        );

        LOVE20ExtensionGroupService groupService = LOVE20ExtensionGroupService(
            extension
        );
        assertEq(groupService.factory(), address(factory));
    }

    function test_CreateExtension_SetsCorrectGroupActionAddress() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            groupActionAddress,
            MAX_RECIPIENTS
        );

        LOVE20ExtensionGroupService groupService = LOVE20ExtensionGroupService(
            extension
        );
        assertEq(groupService.GROUP_ACTION_ADDRESS(), groupActionAddress);
    }

    function test_CreateExtension_MultipleExtensions() public {
        token.approve(address(factory), 3e18);

        address ext1 = factory.createExtension(
            address(token),
            groupActionAddress,
            MAX_RECIPIENTS
        );

        address ext2 = factory.createExtension(
            address(token),
            groupActionAddress,
            5 // different max recipients
        );

        address ext3 = factory.createExtension(
            address(token),
            groupActionAddress,
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
            groupActionAddress,
            MAX_RECIPIENTS
        );

        (
            address tokenAddress,
            address groupActionAddr,
            uint256 maxRecipients
        ) = factory.extensionParams(extension);

        assertEq(tokenAddress, address(token));
        assertEq(groupActionAddr, groupActionAddress);
        assertEq(maxRecipients, MAX_RECIPIENTS);
    }

    function test_ExtensionParams_ZeroForNonExistent() public view {
        (
            address tokenAddress,
            address groupActionAddr,
            uint256 maxRecipients
        ) = factory.extensionParams(address(0x123));

        assertEq(tokenAddress, address(0));
        assertEq(groupActionAddr, address(0));
        assertEq(maxRecipients, 0);
    }

    // ============ Exists Tests ============

    function test_Exists_ReturnsTrueForCreated() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            groupActionAddress,
            MAX_RECIPIENTS
        );

        assertTrue(factory.exists(extension));
    }

    function test_Exists_ReturnsFalseForNonExistent() public view {
        assertFalse(factory.exists(address(0x123)));
        assertFalse(factory.exists(address(0)));
    }
}

