// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    ILOVE20ExtensionBaseGroupTokenJoin
} from "./ILOVE20ExtensionBaseGroupTokenJoin.sol";
import {IGroupManualScore} from "./base/IGroupManualScore.sol";
import {IGroupReward} from "./base/IGroupReward.sol";

/// @title ILOVE20ExtensionBaseGroupTokenJoin
/// @notice Interface for token join group extensions
interface ILOVE20ExtensionBaseGroupTokenJoinManualScore is
    ILOVE20ExtensionBaseGroupTokenJoin,
    IGroupManualScore,
    IGroupReward
{}
