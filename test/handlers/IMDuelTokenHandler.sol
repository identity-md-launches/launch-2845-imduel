// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IMDuelToken} from "src/IMDuelToken.sol";

/// @dev A closed accounting domain: five senders and one recipient-only token contract.
/// Ghost credits/debits record successful call inputs, never balances returned by the token.
/// Grants and cumulative spending are tracked independently for every owner/spender pair.
contract IMDuelTokenHandler is Test {
    uint256 public constant SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public constant SENDERS = 5;
    uint256 public constant ACCOUNTS = 6;

    IMDuelToken public immutable token;
    address[6] public accounts;
    mapping(address => uint256) public credits;
    mapping(address => uint256) public debits;
    mapping(address => mapping(address => uint256)) public granted;
    mapping(address => mapping(address => uint256)) public spent;

    constructor() {
        accounts[0] = address(this);
        accounts[1] = makeAddr("invariant.alice");
        accounts[2] = makeAddr("invariant.bob");
        accounts[3] = makeAddr("invariant.carol");
        accounts[4] = makeAddr("invariant.dave");
        token = new IMDuelToken();
        accounts[5] = address(token);
        credits[address(this)] = SUPPLY;

        // Fund every sender through the real token. No deal/store/etch shortcuts for token state.
        for (uint256 i = 1; i < SENDERS; ++i) {
            _transfer(address(this), accounts[i], SUPPLY / SENDERS);
        }
        // Ensure delegated actions have reachable positive inputs from the beginning.
        for (uint256 i; i < SENDERS; ++i) {
            _approve(accounts[i], accounts[(i + 1) % SENDERS], SUPPLY / SENDERS);
        }
    }

    function transfer(uint256 senderSeed, uint256 recipientSeed, uint256 amountSeed) external {
        address sender = _sender(senderSeed);
        address recipient = accounts[recipientSeed % ACCOUNTS];
        _transfer(sender, recipient, _amount(amountSeed, token.balanceOf(sender)));
    }

    function selfTransfer(uint256 senderSeed, uint256 amountSeed) external {
        address sender = _sender(senderSeed);
        uint256 beforeBalance = token.balanceOf(sender);
        _transfer(sender, sender, _amount(amountSeed, beforeBalance));
        assertEq(token.balanceOf(sender), beforeBalance, "self-transfer changed balance");
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        uint256 mode = amountSeed % 6;
        uint256 amount = amountSeed;
        if (mode == 0) amount = 0;
        else if (mode == 1) amount = 1;
        else if (mode == 2) amount = type(uint256).max;
        else if (mode == 3) amount = type(uint256).max - 1;
        else if (mode == 4) amount = bound(amountSeed, 0, SUPPLY);
        _approve(_sender(ownerSeed), _sender(spenderSeed), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed, uint256 amountSeed) external {
        address owner = _sender(ownerSeed);
        address delegate = _sender(spenderSeed);
        uint256 balance = token.balanceOf(owner);
        uint256 authorized = granted[owner][delegate];
        if (authorized != type(uint256).max) authorized -= spent[owner][delegate];
        uint256 limit = balance < authorized ? balance : authorized;
        _transferFrom(owner, delegate, accounts[recipientSeed % ACCOUNTS], _amount(amountSeed, limit));
    }

    function approveAndSpend(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 recipientSeed,
        uint256 amountSeed,
        bool infinite
    ) external {
        address owner = _sender(ownerSeed);
        address delegate = _sender(spenderSeed);
        uint256 amount = _amount(amountSeed, token.balanceOf(owner));
        _approve(owner, delegate, infinite ? type(uint256).max : amount);
        _transferFrom(owner, delegate, accounts[recipientSeed % ACCOUNTS], amount);
    }

    function revokeAndRejectSpend(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = _sender(ownerSeed);
        address delegate = _sender(spenderSeed);
        _approve(owner, delegate, 0);
        _reject(
            delegate,
            abi.encodeCall(token.transferFrom, (owner, delegate, 1)),
            abi.encodeWithSelector(IMDuelToken.InsufficientAllowance.selector, delegate, 0, 1)
        );
    }

    function rejectOverdraw(uint256 senderSeed, uint256 recipientSeed, bool maximum) external {
        address sender = _sender(senderSeed);
        uint256 balance = token.balanceOf(sender);
        uint256 amount = maximum ? type(uint256).max : balance + 1;
        _reject(
            sender,
            abi.encodeCall(token.transfer, (accounts[recipientSeed % ACCOUNTS], amount)),
            abi.encodeWithSelector(IMDuelToken.InsufficientBalance.selector, sender, balance, amount)
        );
    }

    function rejectDelegatedOverdraw(uint256 ownerSeed, uint256 spenderSeed, bool infinite) external {
        address owner = _sender(ownerSeed);
        address delegate = _sender(spenderSeed);
        uint256 balance = token.balanceOf(owner);
        uint256 amount = balance + 1;
        // Authorization is sufficient, so this reaches the balance failure AFTER allowance spending.
        _approve(owner, delegate, infinite ? type(uint256).max : amount);
        _reject(
            delegate,
            abi.encodeCall(token.transferFrom, (owner, delegate, amount)),
            abi.encodeWithSelector(IMDuelToken.InsufficientBalance.selector, owner, balance, amount)
        );
    }

    function rejectOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = _sender(ownerSeed);
        address delegate = _sender(spenderSeed);
        uint256 balance = token.balanceOf(owner);
        // Prefer a funded, otherwise valid transfer; empty owners still exercise allowance rejection.
        uint256 amount = balance == 0 ? 1 : bound(amountSeed, 1, balance);
        _approve(owner, delegate, amount - 1);
        _reject(
            delegate,
            abi.encodeCall(token.transferFrom, (owner, delegate, amount)),
            abi.encodeWithSelector(IMDuelToken.InsufficientAllowance.selector, delegate, amount - 1, amount)
        );
    }

    function rejectZeroReceiver(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = _sender(ownerSeed);
        uint256 amount = _amount(amountSeed, token.balanceOf(owner));
        bytes memory expected = abi.encodeWithSelector(IMDuelToken.InvalidReceiver.selector, address(0));
        if (delegated) {
            address delegate = _sender(spenderSeed);
            _approve(owner, delegate, amount);
            _reject(delegate, abi.encodeCall(token.transferFrom, (owner, address(0), amount)), expected);
        } else {
            _reject(owner, abi.encodeCall(token.transfer, (address(0), amount)), expected);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        _reject(
            _sender(ownerSeed),
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IMDuelToken.InvalidSpender.selector, address(0))
        );
    }

    function roundTrip(uint256 senderSeed, uint256 recipientSeed, uint256 amountSeed) external {
        uint256 senderIndex = senderSeed % SENDERS;
        address sender = accounts[senderIndex];
        // A distinct, spendable recipient; the token cannot send its own balance back.
        address recipient = accounts[(senderIndex + 1 + recipientSeed % (SENDERS - 1)) % SENDERS];
        uint256 beforeSender = token.balanceOf(sender);
        uint256 beforeRecipient = token.balanceOf(recipient);
        uint256 amount = _amount(amountSeed, beforeSender);
        _transfer(sender, recipient, amount);
        assertEq(token.balanceOf(sender), beforeSender - amount);
        assertEq(token.balanceOf(recipient), beforeRecipient + amount);
        _transfer(recipient, sender, amount);
        assertEq(token.balanceOf(sender), beforeSender, "round-trip lost or created value");
        assertEq(token.balanceOf(recipient), beforeRecipient, "round-trip changed recipient");
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        vm.prank(sender);
        assertTrue(token.transfer(recipient, amount), "valid transfer returned false");
        _recordTransfer(sender, recipient, amount);
    }

    function _transferFrom(address owner, address delegate, address recipient, uint256 amount) internal {
        vm.prank(delegate);
        assertTrue(token.transferFrom(owner, recipient, amount), "valid transferFrom returned false");
        _recordTransfer(owner, recipient, amount);
        if (granted[owner][delegate] != type(uint256).max) spent[owner][delegate] += amount;
    }

    function _recordTransfer(address sender, address recipient, uint256 amount) internal {
        debits[sender] += amount;
        credits[recipient] += amount;
    }

    function _approve(address owner, address delegate, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(delegate, amount), "valid approve returned false");
        granted[owner][delegate] = amount;
        spent[owner][delegate] = 0;
    }

    function _reject(address caller, bytes memory data, bytes memory expectedError) internal {
        vm.prank(caller);
        (bool success, bytes memory returned) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(returned, expectedError, "unexpected failure reason");
        // No ghost updates: every balance and allowance must still match in the invariants.
    }

    function _sender(uint256 seed) internal view returns (address) {
        return accounts[seed % SENDERS];
    }

    function _amount(uint256 seed, uint256 limit) internal pure returns (uint256) {
        uint256 mode = seed % 5;
        if (mode == 0) return 0;
        if (mode == 1) return limit;
        if (mode == 2) return limit == 0 ? 0 : 1;
        return bound(seed, 0, limit);
    }
}
