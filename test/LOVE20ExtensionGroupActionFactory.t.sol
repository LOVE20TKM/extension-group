// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {
    LOVE20ExtensionGroupActionFactory
} from "../src/LOVE20ExtensionGroupActionFactory.sol";
import {LOVE20ExtensionGroupAction} from "../src/LOVE20ExtensionGroupAction.sol";

/**
 * @title LOVE20ExtensionGroupActionFactoryTest
 * @notice Test suite for LOVE20ExtensionGroupActionFactory
 */
contract LOVE20ExtensionGroupActionFactoryTest is BaseGroupTest {
    LOVE20ExtensionGroupActionFactory public factory;

    function setUp() public {
        setUpBase();
        factory = new LOVE20ExtensionGroupActionFactory(address(center));
    }

    // ============ Constructor Tests ============

    function test_Constructor_StoresCenter() public view {
        assertEq(factory.center(), address(center));
    }

    // ============ CreateExtension Tests ============

    function test_CreateExtension_Success() public {
        // Prepare tokens for registration
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(group),
            MIN_GOV_VOTE_RATIO_BPS,
            CAPACITY_MULTIPLIER,
            STAKING_MULTIPLIER,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            MIN_JOIN_AMOUNT
        );

        assertTrue(extension != address(0));
        assertTrue(factory.exists(extension));
    }

    function test_CreateExtension_RegistersExtension() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(group),
            MIN_GOV_VOTE_RATIO_BPS,
            CAPACITY_MULTIPLIER,
            STAKING_MULTIPLIER,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            MIN_JOIN_AMOUNT
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
            address(group),
            MIN_GOV_VOTE_RATIO_BPS,
            CAPACITY_MULTIPLIER,
            STAKING_MULTIPLIER,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            MIN_JOIN_AMOUNT
        );

        uint256 balanceAfter = token.balanceOf(address(this));
        assertEq(balanceBefore - balanceAfter, 1e18);
        assertEq(token.balanceOf(extension), 1e18);
    }

    function test_CreateExtension_SetsCorrectFactory() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(group),
            MIN_GOV_VOTE_RATIO_BPS,
            CAPACITY_MULTIPLIER,
            STAKING_MULTIPLIER,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            MIN_JOIN_AMOUNT
        );

        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(
            extension
        );
        assertEq(groupAction.factory(), address(factory));
    }

    function test_CreateExtension_MultipleExtensions() public {
        token.approve(address(factory), 3e18);

        address ext1 = factory.createExtension(
            address(token),
            address(group),
            MIN_GOV_VOTE_RATIO_BPS,
            CAPACITY_MULTIPLIER,
            STAKING_MULTIPLIER,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            MIN_JOIN_AMOUNT
        );

        address ext2 = factory.createExtension(
            address(token),
            address(group),
            200, // different ratio
            CAPACITY_MULTIPLIER,
            STAKING_MULTIPLIER,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            MIN_JOIN_AMOUNT
        );

        address ext3 = factory.createExtension(
            address(token),
            address(group),
            300,
            CAPACITY_MULTIPLIER,
            STAKING_MULTIPLIER,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            MIN_JOIN_AMOUNT
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
            address(group),
            MIN_GOV_VOTE_RATIO_BPS,
            CAPACITY_MULTIPLIER,
            STAKING_MULTIPLIER,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            MIN_JOIN_AMOUNT
        );

        (
            address tokenAddress,
            address groupAddress,
            uint256 minGovernanceVoteRatio,
            uint256 capacityMultiplier,
            uint256 stakingMultiplier,
            uint256 maxJoinAmountMultiplier,
            uint256 minJoinAmount
        ) = factory.extensionParams(extension);

        assertEq(tokenAddress, address(token));
        assertEq(groupAddress, address(group));
        assertEq(minGovernanceVoteRatio, MIN_GOV_VOTE_RATIO_BPS);
        assertEq(capacityMultiplier, CAPACITY_MULTIPLIER);
        assertEq(stakingMultiplier, STAKING_MULTIPLIER);
        assertEq(maxJoinAmountMultiplier, MAX_JOIN_AMOUNT_MULTIPLIER);
        assertEq(minJoinAmount, MIN_JOIN_AMOUNT);
    }

    function test_ExtensionParams_ZeroForNonExistent() public view {
        (
            address tokenAddress,
            address groupAddress,
            uint256 minGovernanceVoteRatio,
            uint256 capacityMultiplier,
            uint256 stakingMultiplier,
            uint256 maxJoinAmountMultiplier,
            uint256 minJoinAmount
        ) = factory.extensionParams(address(0x123));

        assertEq(tokenAddress, address(0));
        assertEq(groupAddress, address(0));
        assertEq(minGovernanceVoteRatio, 0);
        assertEq(capacityMultiplier, 0);
        assertEq(stakingMultiplier, 0);
        assertEq(maxJoinAmountMultiplier, 0);
        assertEq(minJoinAmount, 0);
    }

    // ============ Exists Tests ============

    function test_Exists_ReturnsTrueForCreated() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(group),
            MIN_GOV_VOTE_RATIO_BPS,
            CAPACITY_MULTIPLIER,
            STAKING_MULTIPLIER,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            MIN_JOIN_AMOUNT
        );

        assertTrue(factory.exists(extension));
    }

    function test_Exists_ReturnsFalseForNonExistent() public view {
        assertFalse(factory.exists(address(0x123)));
        assertFalse(factory.exists(address(0)));
    }
}

