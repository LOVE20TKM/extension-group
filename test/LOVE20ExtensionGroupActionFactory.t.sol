// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {
    LOVE20ExtensionGroupActionFactory
} from "../src/LOVE20ExtensionGroupActionFactory.sol";
import {
    ILOVE20ExtensionGroupActionFactory
} from "../src/interface/ILOVE20ExtensionGroupActionFactory.sol";
import {
    LOVE20ExtensionGroupAction
} from "../src/LOVE20ExtensionGroupAction.sol";
import {LOVE20GroupDistrust} from "../src/LOVE20GroupDistrust.sol";
import {MockGroupToken} from "./mocks/MockGroupToken.sol";

/**
 * @title LOVE20ExtensionGroupActionFactoryTest
 * @notice Test suite for LOVE20ExtensionGroupActionFactory
 */
contract LOVE20ExtensionGroupActionFactoryTest is BaseGroupTest {
    LOVE20ExtensionGroupActionFactory public factory;
    LOVE20GroupDistrust public groupDistrust;

    // Event declaration for testing
    event ExtensionCreate(
        address indexed extension,
        address indexed tokenAddress,
        address groupManagerAddress,
        address groupDistrustAddress,
        address stakeTokenAddress,
        address joinTokenAddress,
        uint256 activationStakeAmount,
        uint256 maxJoinAmountMultiplier,
        uint256 verifyCapacityMultiplier
    );

    function setUp() public {
        setUpBase();

        // Deploy GroupDistrust singleton
        groupDistrust = new LOVE20GroupDistrust(
            address(center),
            address(verify),
            address(group)
        );

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
            address(groupManager),
            address(groupDistrust),
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            CAPACITY_FACTOR
        );

        assertTrue(extension != address(0));
        assertTrue(factory.exists(extension));
    }

    function test_CreateExtension_RegistersExtension() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(groupManager),
            address(groupDistrust),
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
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
            address(groupManager),
            address(groupDistrust),
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
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
            address(groupManager),
            address(groupDistrust),
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            CAPACITY_FACTOR
        );

        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(
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
            address(groupManager),
            address(groupDistrust),
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            CAPACITY_FACTOR
        );

        address ext2 = factory.createExtension(
            address(token2),
            address(groupManager),
            address(groupDistrust),
            address(token2),
            address(token2), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            CAPACITY_FACTOR
        );

        address ext3 = factory.createExtension(
            address(token3),
            address(groupManager),
            address(groupDistrust),
            address(token3),
            address(token3), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
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
            address(groupManager),
            address(groupDistrust),
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            CAPACITY_FACTOR
        );

        (
            address tokenAddress,
            address groupManagerAddress,
            address groupDistrustAddress,
            address stakeTokenAddress,
            address joinTokenAddress,
            uint256 activationStakeAmount,
            uint256 maxJoinAmountMultiplier,
            uint256 verifyCapacityMultiplier
        ) = factory.extensionParams(extension);

        assertEq(tokenAddress, address(token));
        assertEq(groupManagerAddress, address(groupManager));
        assertEq(groupDistrustAddress, address(groupDistrust));
        assertEq(stakeTokenAddress, address(token));
        assertEq(joinTokenAddress, address(token));
        assertEq(activationStakeAmount, GROUP_ACTIVATION_STAKE_AMOUNT);
        assertEq(maxJoinAmountMultiplier, MAX_JOIN_AMOUNT_MULTIPLIER);
        assertEq(verifyCapacityMultiplier, CAPACITY_FACTOR);
    }

    function test_ExtensionParams_ZeroForNonExistent() public view {
        (
            address tokenAddress,
            address groupManagerAddress,
            address groupDistrustAddress,
            address stakeTokenAddress,
            address joinTokenAddress,
            uint256 activationStakeAmount,
            uint256 maxJoinAmountMultiplier,
            uint256 verifyCapacityMultiplier
        ) = factory.extensionParams(address(0x123));

        assertEq(tokenAddress, address(0));
        assertEq(groupManagerAddress, address(0));
        assertEq(groupDistrustAddress, address(0));
        assertEq(stakeTokenAddress, address(0));
        assertEq(joinTokenAddress, address(0));
        assertEq(activationStakeAmount, 0);
        assertEq(maxJoinAmountMultiplier, 0);
        assertEq(verifyCapacityMultiplier, 0);
    }

    // ============ Exists Tests ============

    function test_Exists_ReturnsTrueForCreated() public {
        token.approve(address(factory), 1e18);

        address extension = factory.createExtension(
            address(token),
            address(groupManager),
            address(groupDistrust),
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
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
        emit ExtensionCreate({
            extension: expectedExtension,
            tokenAddress: address(token),
            groupManagerAddress: address(groupManager),
            groupDistrustAddress: address(groupDistrust),
            stakeTokenAddress: address(token),
            joinTokenAddress: address(token),
            activationStakeAmount: GROUP_ACTIVATION_STAKE_AMOUNT,
            maxJoinAmountMultiplier: MAX_JOIN_AMOUNT_MULTIPLIER,
            verifyCapacityMultiplier: CAPACITY_FACTOR
        });

        address extension = factory.createExtension(
            address(token),
            address(groupManager),
            address(groupDistrust),
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            CAPACITY_FACTOR
        );

        assertEq(extension, expectedExtension);
    }
}
