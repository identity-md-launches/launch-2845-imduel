// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IMDuelToken} from "src/IMDuelToken.sol";
import {IMDuelTokenHandler} from "./handlers/IMDuelTokenHandler.sol";

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract IMDuelTokenInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    IMDuelTokenHandler internal handler;
    IMDuelToken internal token;

    function setUp() public {
        handler = new IMDuelTokenHandler();
        token = handler.token();

        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.selfTransfer.selector;
        selectors[2] = handler.approve.selector;
        selectors[3] = handler.transferFrom.selector;
        selectors[4] = handler.approveAndSpend.selector;
        selectors[5] = handler.revokeAndRejectSpend.selector;
        selectors[6] = handler.rejectOverdraw.selector;
        selectors[7] = handler.rejectDelegatedOverdraw.selector;
        selectors[8] = handler.rejectOverAllowance.selector;
        selectors[9] = handler.rejectZeroReceiver.selector;
        selectors[10] = handler.rejectZeroSpender.selector;
        selectors[11] = handler.roundTrip.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyEqualsSumOfAllReachableBalances() public view {
        uint256 sum;
        for (uint256 i; i < handler.ACCOUNTS(); ++i) {
            sum += token.balanceOf(handler.accounts(i));
        }
        assertEq(sum, SUPPLY, "tokens were created, destroyed or diverted");
        assertEq(token.totalSupply(), SUPPLY, "fixed supply changed");
        assertEq(token.balanceOf(address(0)), 0, "zero address received tokens");
    }

    function invariant_eachHolderMatchesItsTransferHistory() public view {
        for (uint256 i; i < handler.ACCOUNTS(); ++i) {
            address account = handler.accounts(i);
            assertEq(
                token.balanceOf(account) + handler.debits(account),
                handler.credits(account),
                "holder balance disagrees with cumulative transfers"
            );
        }
    }

    function invariant_onlyAuthorizedSpendingChangesAllowances() public view {
        for (uint256 i; i < handler.ACCOUNTS(); ++i) {
            address owner = handler.accounts(i);
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            for (uint256 j; j < handler.ACCOUNTS(); ++j) {
                address delegate = handler.accounts(j);
                uint256 approved = handler.granted(owner, delegate);
                uint256 used = handler.spent(owner, delegate);
                if (approved == type(uint256).max) {
                    assertEq(token.allowance(owner, delegate), type(uint256).max, "infinite approval was consumed");
                } else {
                    assertLe(used, approved, "spender exceeded owner's grant");
                    assertEq(token.allowance(owner, delegate), approved - used, "allowance changed without permission");
                }
            }
        }
    }

    function invariant_metadataRemainsAsSpecified() public view {
        assertEq(token.name(), "IMDuel");
        assertEq(token.symbol(), "IMDUEL");
        assertEq(token.decimals(), 18);
    }
}
