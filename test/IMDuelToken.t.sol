// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IMDuelToken} from "../src/IMDuelToken.sol";

/// @notice Stands in for the launch factory: deploys the token so the supply is minted to this
///         contract, then forwards it the way the factory does (distributor, pool, remainder).
contract FactoryStub {
    IMDuelToken public token;

    function deployToken() external returns (IMDuelToken) {
        token = new IMDuelToken();
        return token;
    }

    function move(address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract IMDuelTokenTest is Test {
    uint256 constant SUPPLY = 1_000_000_000 ether;

    IMDuelToken token;
    address deployer = makeAddr("deployer");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address spender = makeAddr("spender");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(deployer);
        token = new IMDuelToken();
    }

    // ------------------------------------------------------------------------
    // Metadata and supply
    // ------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "IMDuel");
        assertEq(token.symbol(), "IMDUEL");
        assertEq(token.decimals(), 18);
    }

    function test_constants() public view {
        assertEq(token.NAME(), "IMDuel");
        assertEq(token.SYMBOL(), "IMDUEL");
        assertEq(token.DECIMALS(), 18);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), alice, SUPPLY);
        vm.prank(alice);
        new IMDuelToken();
    }

    function test_constructorMintsToWhoeverDeploys_asTheFactoryWill() public {
        FactoryStub factory = new FactoryStub();
        IMDuelToken launched = factory.deployToken();
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);
    }

    // ------------------------------------------------------------------------
    // transfer
    // ------------------------------------------------------------------------

    function test_transfer_movesExactAmountAndEmits() public {
        uint256 amount = 1_234 ether;
        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, alice, amount);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transfer_zeroAmountSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transfer_toSelfKeepsBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 100 ether);
        vm.prank(alice);
        assertTrue(token.transfer(alice, 100 ether));
        assertEq(token.balanceOf(alice), 100 ether);
    }

    function test_transfer_wholeBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_transfer_revertsWhenBalanceInsufficient() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InsufficientBalance.selector, alice, 10 ether, 10 ether + 1));
        vm.prank(alice);
        token.transfer(bob, 10 ether + 1);
    }

    function test_transfer_revertsFromEmptyAccount() public {
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InsufficientBalance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transfer(alice, 1);
    }

    function test_transfer_revertsToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 1);
    }

    // ------------------------------------------------------------------------
    // approve / allowance / transferFrom
    // ------------------------------------------------------------------------

    function test_approve_setsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(deployer, spender, 500 ether);
        vm.prank(deployer);
        assertTrue(token.approve(spender, 500 ether));
        assertEq(token.allowance(deployer, spender), 500 ether);
    }

    function test_approve_overwritesPreviousAllowance() public {
        vm.startPrank(deployer);
        token.approve(spender, 500 ether);
        token.approve(spender, 7 ether);
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 7 ether);
    }

    function test_approve_zeroClearsAllowance() public {
        vm.startPrank(deployer);
        token.approve(spender, 500 ether);
        token.approve(spender, 0);
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_approve_revertsForZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 1);
    }

    function test_approve_doesNotNeedBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        assertEq(token.allowance(alice, spender), SUPPLY);
    }

    function test_transferFrom_movesAndDecrementsAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 500 ether);

        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, bob, 200 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, 200 ether));

        assertEq(token.balanceOf(bob), 200 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 200 ether);
        assertEq(token.allowance(deployer, spender), 300 ether);
        assertEq(token.balanceOf(spender), 0, "the spender itself received nothing");
    }

    function test_transferFrom_exactAllowanceSpendsItToZero() public {
        vm.prank(deployer);
        token.approve(spender, 200 ether);
        vm.prank(spender);
        token.transferFrom(deployer, bob, 200 ether);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_transferFrom_infiniteAllowanceIsNotDecremented() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1_000 ether);
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(bob), 1_000 ether);
    }

    function test_transferFrom_revertsWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1);
    }

    function test_transferFrom_revertsWhenAllowanceInsufficient() public {
        vm.prank(deployer);
        token.approve(spender, 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IMDuelToken.InsufficientAllowance.selector, spender, 100 ether, 100 ether + 1)
        );
        vm.prank(spender);
        token.transferFrom(deployer, bob, 100 ether + 1);
    }

    function test_transferFrom_revertsWhenOwnerBalanceInsufficient() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.prank(alice);
        token.approve(spender, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InsufficientBalance.selector, alice, 10 ether, 11 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 11 ether);
        // The failed attempt did not touch the allowance.
        assertEq(token.allowance(alice, spender), 100 ether);
    }

    function test_transferFrom_revertsToZeroAddress() public {
        vm.prank(deployer);
        token.approve(spender, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), 1);
    }

    function test_transferFrom_spendsOnlyTheCallersOwnAllowance() public {
        // deployer approves `spender`, but `bob` tries to use that allowance: arbitrary-send is impossible.
        vm.prank(deployer);
        token.approve(spender, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFrom_byOwnerStillNeedsSelfAllowance() public {
        // Holders move their own tokens with `transfer`; `transferFrom` on oneself follows the same rules.
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(deployer, bob, 1);
    }

    // ------------------------------------------------------------------------
    // No privileged surface
    // ------------------------------------------------------------------------

    function test_noMintOrAdminSelectorExists() public {
        string[12] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "transferOwnership(address)",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, type(uint128).max);
            vm.prank(deployer);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(alice);
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_deployerHasNoPowerOverHolders() public {
        vm.prank(deployer);
        token.transfer(alice, 1_000 ether);

        // Deployer cannot pull from a holder without allowance.
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(alice, deployer, 1);

        // Holder is unaffected and can still move freely.
        assertEq(token.balanceOf(alice), 1_000 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 400 ether));
        assertEq(token.balanceOf(bob), 400 ether);
    }

    function test_receiveEtherIsRejected() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "the token must not accept ether");
        assertEq(address(token).balance, 0);
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ------------------------------------------------------------------------
    // Launch flows move exactly what they say
    // ------------------------------------------------------------------------

    function test_launchFlows_arriveWhole() public {
        FactoryStub factory = new FactoryStub();
        IMDuelToken launched = factory.deployToken();
        address distributor = makeAddr("distributor");
        address claimant = makeAddr("claimant");
        address remainderTo = makeAddr("remainderTo");

        uint256 swarm = SUPPLY * 1_000 / 10_000;
        uint256 pool = SUPPLY * 8_000 / 10_000;
        uint256 remainder = SUPPLY - swarm - pool;

        assertTrue(factory.move(distributor, swarm));
        assertEq(launched.balanceOf(distributor), swarm, "swarm share short");
        vm.prank(distributor);
        assertTrue(launched.transfer(claimant, swarm));
        assertEq(launched.balanceOf(claimant), swarm, "claim short");
        assertEq(launched.balanceOf(distributor), 0);

        assertTrue(factory.move(remainderTo, remainder));
        assertEq(launched.balanceOf(remainderTo), remainder, "remainder short");
        assertEq(launched.balanceOf(address(factory)), pool, "pool share short");
        assertEq(launched.totalSupply(), SUPPLY, "supply changed");
    }

    // ------------------------------------------------------------------------
    // Fuzz
    // ------------------------------------------------------------------------

    function testFuzz_transfer_conservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        if (to == deployer) {
            assertEq(token.balanceOf(deployer), SUPPLY);
        } else {
            assertEq(token.balanceOf(to), amount);
            assertEq(token.balanceOf(deployer), SUPPLY - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transfer_revertsAboveBalance(uint256 funded, uint256 attempt) public {
        funded = bound(funded, 0, SUPPLY - 1);
        attempt = bound(attempt, funded + 1, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, funded);
        vm.expectRevert(abi.encodeWithSelector(IMDuelToken.InsufficientBalance.selector, alice, funded, attempt));
        vm.prank(alice);
        token.transfer(bob, attempt);
    }

    function testFuzz_transferFrom_respectsAllowance(uint256 allowed, uint256 attempt) public {
        allowed = bound(allowed, 0, SUPPLY);
        attempt = bound(attempt, 0, SUPPLY);
        vm.prank(deployer);
        token.approve(spender, allowed);
        vm.prank(spender);
        if (attempt > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(IMDuelToken.InsufficientAllowance.selector, spender, allowed, attempt)
            );
            token.transferFrom(deployer, bob, attempt);
        } else {
            assertTrue(token.transferFrom(deployer, bob, attempt));
            assertEq(token.balanceOf(bob), attempt);
            assertEq(token.allowance(deployer, spender), allowed - attempt);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approve_setsExactValue(address who, uint256 value) public {
        vm.assume(who != address(0));
        vm.prank(alice);
        assertTrue(token.approve(who, value));
        assertEq(token.allowance(alice, who), value);
    }
}
