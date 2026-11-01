// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {IMDuelToken} from "../src/IMDuelToken.sol";

/// @title Deploy script for IMDuelToken
/// @notice Reviewable reference deployment. The IdentityMD launch deploys the token itself through its
///         factory, so this script is for local forks and audits, not for the launch. It reads nothing
///         from the environment: the token takes no constructor arguments and the whole supply goes
///         to whichever account runs the transaction.
contract DeployIMDuelToken is Script {
    /// @notice Deploys the token. Tests call this directly; the supply is minted to `msg.sender`
    ///         of the deployment transaction (this contract when called from a test).
    function deploy() public returns (IMDuelToken token) {
        token = new IMDuelToken();
    }

    /// @notice Broadcasts the deployment with the signer `forge script` is given on the command line.
    function run() external returns (IMDuelToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
