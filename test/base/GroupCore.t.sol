// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "../utils/BaseGroupTest.sol";
import {GroupCore} from "../../src/base/GroupCore.sol";
import {IGroupCore} from "../../src/interface/base/IGroupCore.sol";
import {ExtensionReward} from "@extension/src/base/ExtensionReward.sol";
import {
    IExtensionReward
} from "@extension/src/interface/base/IExtensionReward.sol";

/**
 * @title MockGroupCore
 * @notice Concrete implementation of GroupCore for testing
 */
contract MockGroupCore is GroupCore {
    constructor(
        address factory_,
        address tokenAddress_,
        address groupManagerAddress_,
        address stakeTokenAddress_,
        uint256 groupActivationStakeAmount_
    )
        GroupCore(
            factory_,
            tokenAddress_,
            groupManagerAddress_,
            stakeTokenAddress_,
            groupActivationStakeAmount_
        )
    {}

    function isJoinedValueCalculated() external pure returns (bool) {
        return false;
    }

    function joinedValue() external pure returns (uint256) {
        return 0;
    }

    function joinedValueByAccount(address) external pure returns (uint256) {
        return 0;
    }

    function _calculateReward(
        uint256,
        address
    ) internal pure override returns (uint256) {
        return 0;
    }
}

/**
 * @title GroupCoreTest
 * @notice Test suite for GroupCore - tests immutable config parameters
 */
contract GroupCoreTest is BaseGroupTest {
    MockGroupCore public groupCore;

    function setUp() public {
        setUpBase();

        // Deploy GroupCore
        groupCore = new MockGroupCore(
            address(mockFactory),
            address(token),
            address(groupManager),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT
        );

        // Register extension
        token.mint(address(this), 1e18);
        token.approve(address(mockFactory), type(uint256).max);
        mockFactory.registerExtension(address(groupCore), address(token));
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsImmutables() public view {
        assertEq(groupCore.GROUP_MANAGER_ADDRESS(), address(groupManager));
        assertEq(groupCore.GROUP_ADDRESS(), address(group));
        assertEq(groupCore.STAKE_TOKEN_ADDRESS(), address(token));
        assertEq(
            groupCore.GROUP_ACTIVATION_STAKE_AMOUNT(),
            GROUP_ACTIVATION_STAKE_AMOUNT
        );
    }
}
