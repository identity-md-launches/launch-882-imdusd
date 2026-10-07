// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {Token} from "../src/Token.sol";

contract TokenHandler is Test {
    Token private immutable token;
    address[3] public actors = [address(0xA11CE), address(0xB0B), address(0xCA201)];

    // The ledger starts from the specified distribution and changes only from call inputs.
    // Never copy observed token state into these expectations: that could hide a bad transfer.
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Token token_) {
        token = token_;
        expectedBalance[actors[0]] = 1_000_000_000 ether;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 3];
        address to = actors[toSeed % 3];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        _approve(owner, spender, amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        address to = actors[toSeed % 3];
        uint256 available = expectedBalance[owner];
        uint256 allowance = expectedAllowance[owner][spender];
        amount = bound(amount, 0, available < allowance ? available : allowance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _move(owner, to, amount);
        if (allowance != type(uint256).max) expectedAllowance[owner][spender] -= amount;
    }

    function approveInfinite(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(actors[ownerSeed % 3], actors[spenderSeed % 3], type(uint256).max);
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(actors[ownerSeed % 3], actors[spenderSeed % 3], 0);
    }

    // Exercise positive delegated transfers from funded actors even when no allowance remains.
    // The separate transferFrom action consumes approvals left by earlier calls.
    function approveAndSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        address to = actors[toSeed % 3];
        uint256 available = expectedBalance[owner];
        uint256 amount = available == 0 ? 0 : bound(rawAmount, 1, available);
        _approve(owner, spender, amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _move(owner, to, amount);
        expectedAllowance[owner][spender] = 0;
    }

    function overdraw(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % 3];
        address to = actors[toSeed % 3];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
        // A rejected call must leave the entire ghost ledger unchanged.
    }

    function overspendAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAllowance) external {
        address owner = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        uint256 approved = bound(rawAllowance, 0, 1_000_000_000 ether);
        _approve(owner, spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, actors[(ownerSeed % 3 + 1) % 3], approved + 1);
    }

    function delegatedOverdraw(uint256 ownerSeed, uint256 spenderSeed, bool infinite) external {
        address owner = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + 1;
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, actors[(ownerSeed % 3 + 1) % 3], amount);
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        uint256 amount = bound(rawAmount, 0, expectedBalance[owner]);
        _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(owner);
        token.transfer(address(0), amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _move(address from, address to, uint256 amount) private {
        if (from != to) {
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract TokenInvariantTest is StdInvariant, Test {
    Token private token;
    TokenHandler private handler;

    function setUp() public {
        token = new Token();
        handler = new TokenHandler(token);
        assertTrue(token.transfer(handler.actors(0), 1_000_000_000 ether));
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.approveInfinite.selector;
        selectors[4] = TokenHandler.revoke.selector;
        selectors[5] = TokenHandler.approveAndSpend.selector;
        selectors[6] = TokenHandler.overdraw.selector;
        selectors[7] = TokenHandler.overspendAllowance.selector;
        selectors[8] = TokenHandler.delegatedOverdraw.selector;
        selectors[9] = TokenHandler.rejectZeroRecipient.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyAndBalancesAreConserved() public view {
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        uint256 sum;
        for (uint256 i; i < 3; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor), "holder's balance differs from ledger");
            sum += token.balanceOf(actor);
        }
        assertEq(sum, 1_000_000_000 ether);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_allowancesMatchAuthorizations() public view {
        // Checking every pair also catches changes to uninvolved owners and spenders.
        for (uint256 i; i < 3; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 3; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
        }
    }

    function afterInvariant() public {
        // Every holder must still be able to move its entire balance after any sequence.
        address recipient = address(this);
        for (uint256 i; i < 3; ++i) {
            address owner = handler.actors(i);
            uint256 amount = handler.expectedBalance(owner);
            vm.prank(owner);
            assertTrue(token.transfer(recipient, amount));
            assertEq(token.balanceOf(owner), 0);
        }
        assertEq(token.balanceOf(recipient), 1_000_000_000 ether);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        invariant_allowancesMatchAuthorizations();
    }
}
