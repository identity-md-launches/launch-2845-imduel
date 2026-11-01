// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployIMDuelToken} from "../script/DeployIMDuelToken.s.sol";
import {IMDuelToken} from "../src/IMDuelToken.sol";

contract DeployIMDuelTokenTest is Test {
    function test_deployMintsSupplyToTheDeployingAccount() public {
        DeployIMDuelToken script = new DeployIMDuelToken();
        IMDuelToken token = script.deploy();
        // The script contract is `msg.sender` of the constructor, so it holds the supply.
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.balanceOf(address(script)), 1_000_000_000 ether);
        assertEq(token.name(), "IMDuel");
        assertEq(token.symbol(), "IMDUEL");
        assertEq(token.decimals(), 18);
    }
}
