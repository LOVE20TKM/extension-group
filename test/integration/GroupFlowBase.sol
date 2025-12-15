// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    TestGroupFlowHelper,
    GroupUserParams,
    FlowUserParams
} from "./helper/TestGroupFlowHelper.sol";

/// @title GroupFlowBase
/// @notice Base test contract for Group extension integration tests
contract GroupFlowBase is Test {
    TestGroupFlowHelper public h;

    // Test users
    GroupUserParams public bob;
    GroupUserParams public alice;
    GroupUserParams public charlie;

    // Regular flow users (for members)
    FlowUserParams public member1;
    FlowUserParams public member2;
    FlowUserParams public member3;

    uint256 constant MINT_AMOUNT = 100000e18;

    function setUp() public virtual {
        h = new TestGroupFlowHelper();

        // Create group owners with NFTs
        bob = h.createGroupUser(
            "bob",
            h.firstTokenAddress(),
            MINT_AMOUNT,
            "BobsGroup"
        );
        alice = h.createGroupUser(
            "alice",
            h.firstTokenAddress(),
            MINT_AMOUNT,
            "AlicesGroup"
        );

        // Create regular members
        member1 = h.createUser(
            "member1",
            h.firstTokenAddress(),
            MINT_AMOUNT / 10
        );
        member2 = h.createUser(
            "member2",
            h.firstTokenAddress(),
            MINT_AMOUNT / 10
        );
        member3 = h.createUser(
            "member3",
            h.firstTokenAddress(),
            MINT_AMOUNT / 10
        );
    }
}
