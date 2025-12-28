// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILOVE20Extension} from "@extension/src/interface/ILOVE20Extension.sol";
import {IGroupTokenJoin} from "./base/IGroupTokenJoin.sol";
import {IGroupScore} from "./base/IGroupScore.sol";
import {IGroupDistrust} from "./base/IGroupDistrust.sol";
import {IGroupCore} from "./base/IGroupCore.sol";
import {IGroupReward} from "./base/IGroupReward.sol";

/// @title ILOVE20ExtensionGroupAction
/// @notice Combined interface for group-based action extension with manual scoring
interface ILOVE20ExtensionGroupAction is
    ILOVE20Extension,
    IGroupCore,
    IGroupTokenJoin,
    IGroupScore,
    IGroupDistrust,
    IGroupReward
{}
