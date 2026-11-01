// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IMDuelToken} from "src/IMDuelToken.sol";

/// @dev Supplements the original deployment and ERC-20 examples with boundary and sequence properties.
/// forge-config: default.fuzz.runs = 1000
contract IMDuelTokenPropertiesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    IMDuelToken internal token;
    address internal issuer = makeAddr("properties.issuer");
    address internal alice = makeAddr("properties.alice");
    address internal bob = makeAddr("properties.bob");
    address internal spender = makeAddr("properties.spender");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(issuer);
        token = new IMDuelToken();
    }

    function test_transferOneWeiAndZeroEmitExactEvents() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(issuer, alice, 1);
        vm.prank(issuer);
        assertTrue(token.transfer(alice, 1));

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(bob, alice, 0);
        vm.prank(bob);
        assertTrue(token.transfer(alice, 0));
        _assertBalances(SUPPLY - 1, 1, 0);
    }

    function test_zeroTransferFromNeedsNeitherBalanceNorAllowanceAndEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_zeroTransferFromPreservesExistingAllowance() public {
        _approve(alice, spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, 0));
        assertEq(token.allowance(alice, spender), type(uint256).max - 1);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_zeroAmountStillRejectsZeroReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InvalidReceiver.selector, address(0)));
        vm.prank(issuer);
        token.transfer(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(issuer, address(0), 0);
        assertEq(token.allowance(issuer, spender), 0);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_zeroTransferFromRejectsZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InvalidSender.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
        assertEq(token.allowance(address(0), spender), 0);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_zeroCallerGuards() public {
        // Defensive branches: address(0) cannot originate an ordinary signed transaction.
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(alice, 0);

        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(spender, 0);
        assertEq(token.allowance(address(0), spender), 0);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_zeroSpenderRejectedEvenForZeroAndMaximumApproval() public {
        _approve(issuer, spender, 17);
        uint256[2] memory values = [uint256(0), type(uint256).max];
        for (uint256 i; i < values.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InvalidSpender.selector, address(0)));
            vm.prank(issuer);
            token.approve(address(0), values[i]);
        }
        assertEq(token.allowance(issuer, address(0)), 0);
        assertEq(token.allowance(issuer, spender), 17);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_maximumTransferRevertsWithoutOverflowOrStateChange() public {
        _approve(issuer, spender, 123);
        vm.expectRevert(
            abi.encodeWithSelector(IMDuelToken.InsufficientBalance.selector, issuer, SUPPLY, type(uint256).max)
        );
        vm.prank(issuer);
        token.transfer(alice, type(uint256).max);
        assertEq(token.allowance(issuer, spender), 123);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_selfTransferCannotBypassBalanceCheck() public {
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InsufficientBalance.selector, issuer, SUPPLY, SUPPLY + 1));
        vm.prank(issuer);
        token.transfer(issuer, SUPPLY + 1);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_maximumTransferFromWithInfiniteAllowanceStillChecksBalance() public {
        _approve(issuer, spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IMDuelToken.InsufficientBalance.selector, issuer, SUPPLY, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(issuer, alice, type(uint256).max);
        assertEq(token.allowance(issuer, spender), type(uint256).max);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        uint256 approved = type(uint256).max - 1;
        _approve(issuer, spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(issuer, alice, 1));
        assertEq(token.allowance(issuer, spender), approved - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(issuer, bob, SUPPLY - 1));
        assertEq(token.allowance(issuer, spender), approved - SUPPLY);
        _assertBalances(0, 1, SUPPLY - 1);
    }

    function test_transferFromFullSupplyExhaustsOnlyItsAllowance() public {
        _approve(issuer, spender, SUPPLY);
        _approve(issuer, bob, 29);
        vm.prank(spender);
        assertTrue(token.transferFrom(issuer, alice, SUPPLY));
        assertEq(token.allowance(issuer, spender), 0);
        assertEq(token.allowance(issuer, bob), 29);
        _assertBalances(0, SUPPLY, 0);

        // Return the funds: spending is still forbidden because the allowance, not the balance, is exhausted.
        vm.prank(alice);
        assertTrue(token.transfer(issuer, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(issuer, bob, 1);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_ownerCanUseTransferFromOnlyAfterSelfApproval() public {
        _approve(issuer, issuer, SUPPLY);
        vm.prank(issuer);
        assertTrue(token.transferFrom(issuer, alice, SUPPLY));
        assertEq(token.allowance(issuer, issuer), 0);
        _assertBalances(0, SUPPLY, 0);
    }

    function test_spenderMayBeRecipientWithoutReceivingTwice() public {
        _approve(issuer, alice, SUPPLY);
        vm.prank(alice);
        assertTrue(token.transferFrom(issuer, alice, SUPPLY));
        assertEq(token.allowance(issuer, alice), 0);
        _assertBalances(0, SUPPLY, 0);
    }

    function test_revokingInfiniteAllowanceBlocksFurtherSpends() public {
        _approve(issuer, spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(issuer, alice, 1));
        assertEq(token.allowance(issuer, spender), type(uint256).max);

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(issuer, spender, 0);
        _approve(issuer, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(issuer, alice, 1);
        assertEq(token.allowance(issuer, spender), 0);
        _assertBalances(SUPPLY - 1, 1, 0);
    }

    function test_approvalFromAnotherOwnerCannotAuthorizeASpend() public {
        _approve(alice, spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(issuer, alice, 1);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.allowance(issuer, spender), 0);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_allowanceCannotBeUsedInReverseDirection() public {
        _approve(spender, issuer, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(issuer, alice, 1);
        assertEq(token.allowance(spender, issuer), type(uint256).max);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_tokensSentToTokenContractRemainPartOfSupply() public {
        vm.prank(issuer);
        assertTrue(token.transfer(address(token), 1));
        _approve(issuer, spender, SUPPLY - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(issuer, address(token), SUPPLY - 1));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(issuer), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.allowance(issuer, spender), 0);
    }

    function testFuzz_selfTransferFromPreservesBalanceButConsumesAuthorization(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        _approve(issuer, spender, amount);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(issuer, issuer, amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(issuer, issuer, amount));
        assertEq(token.allowance(issuer, spender), 0);
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_zeroReceiverFailureRestoresFiniteAllowance(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max - 1);
        _approve(issuer, spender, approved);
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(issuer, address(0), amount);
        assertEq(token.allowance(issuer, spender), approved, "failed transfer consumed approval");
        _assertBalances(SUPPLY, 0, 0);

        // The same authorization remains usable for a valid recipient after the failure.
        vm.prank(spender);
        assertTrue(token.transferFrom(issuer, alice, amount));
        assertEq(token.allowance(issuer, spender), approved - amount);
        _assertBalances(SUPPLY - amount, amount, 0);
    }

    function testFuzz_balanceFailureRestoresAllowanceAndCanBeRetried(uint256 funded, uint256 attempted) public {
        funded = bound(funded, 0, SUPPLY - 1);
        attempted = bound(attempted, funded + 1, SUPPLY);
        vm.prank(issuer);
        assertTrue(token.transfer(alice, funded));
        _approve(alice, spender, attempted);
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InsufficientBalance.selector, alice, funded, attempted));
        vm.prank(spender);
        token.transferFrom(alice, bob, attempted);
        assertEq(token.allowance(alice, spender), attempted);
        _assertBalances(SUPPLY - funded, funded, 0);

        vm.prank(issuer);
        assertTrue(token.transfer(alice, attempted - funded));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, attempted));
        assertEq(token.allowance(alice, spender), 0);
        _assertBalances(SUPPLY - attempted, 0, attempted);
    }

    function testFuzz_allowanceFailureIsAtomic(uint256 approved, uint256 attempted) public {
        approved = bound(approved, 0, SUPPLY - 1);
        attempted = bound(attempted, approved + 1, SUPPLY);
        _approve(issuer, spender, approved);
        _approve(issuer, bob, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IMDuelToken.InsufficientAllowance.selector, spender, approved, attempted)
        );
        vm.prank(spender);
        token.transferFrom(issuer, alice, attempted);
        assertEq(token.allowance(issuer, spender), approved);
        assertEq(token.allowance(issuer, bob), type(uint256).max);
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_splitSpendingCannotExceedTheOriginalGrant(uint256 budget, uint256 first) public {
        budget = bound(budget, 1, SUPPLY);
        first = bound(first, 0, budget);
        _approve(issuer, spender, budget);
        vm.prank(spender);
        assertTrue(token.transferFrom(issuer, alice, first));
        assertEq(token.allowance(issuer, spender), budget - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(issuer, bob, budget - first));
        assertEq(token.allowance(issuer, spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(issuer, alice, 1);
        _assertBalances(SUPPLY - budget, first, budget - first);
    }

    function testFuzz_approvalReplacementIsExactAndIsolated(uint256 previous, uint256 replacement) public {
        _approve(issuer, spender, previous);
        _approve(issuer, bob, 41);
        _approve(alice, spender, 53);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(issuer, spender, replacement);
        _approve(issuer, spender, replacement);
        // Repeating an approval is idempotent; it must not accumulate another grant.
        _approve(issuer, spender, replacement);
        assertEq(token.allowance(issuer, spender), replacement);
        assertEq(token.allowance(issuer, bob), 41);
        assertEq(token.allowance(alice, spender), 53);
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_replacingInfiniteApprovalEnforcesTheNewLimit(uint256 replacement) public {
        replacement = bound(replacement, 0, SUPPLY - 1);
        _approve(issuer, spender, type(uint256).max);
        _approve(issuer, spender, replacement);
        vm.expectRevert(
            abi.encodeWithSelector(IMDuelToken.InsufficientAllowance.selector, spender, replacement, replacement + 1)
        );
        vm.prank(spender);
        token.transferFrom(issuer, alice, replacement + 1);
        assertEq(token.allowance(issuer, spender), replacement);
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_transferRoundTripHasNoFeesOrRounding(uint256 amount, uint8 cycles) public {
        amount = bound(amount, 0, SUPPLY);
        cycles = uint8(bound(cycles, 1, 12));
        _approve(issuer, spender, 71);
        for (uint256 i; i < cycles; ++i) {
            vm.prank(issuer);
            assertTrue(token.transfer(alice, amount));
            _assertBalances(SUPPLY - amount, amount, 0);
            vm.prank(alice);
            assertTrue(token.transfer(issuer, amount));
            _assertBalances(SUPPLY, 0, 0);
            assertEq(token.allowance(issuer, spender), 71, "direct transfer changed authorization");
        }
    }

    function testFuzz_splitTransferEqualsSingleTransfer(uint256 total, uint256 first) public {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        vm.prank(issuer);
        IMDuelToken split = new IMDuelToken();
        vm.prank(issuer);
        assertTrue(token.transfer(alice, total));
        vm.startPrank(issuer);
        assertTrue(split.transfer(alice, first));
        assertTrue(split.transfer(alice, total - first));
        vm.stopPrank();
        assertEq(split.balanceOf(issuer), token.balanceOf(issuer));
        assertEq(split.balanceOf(alice), token.balanceOf(alice));
        assertEq(split.totalSupply(), SUPPLY);
        _assertBalances(SUPPLY - total, total, 0);
    }

    function _approve(address owner, address delegate, uint256 value) internal {
        vm.prank(owner);
        assertTrue(token.approve(delegate, value));
    }

    function _assertBalances(uint256 issuerBalance, uint256 aliceBalance, uint256 bobBalance) internal view {
        assertEq(token.balanceOf(issuer), issuerBalance);
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
