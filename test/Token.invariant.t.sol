// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Token} from "../src/Token.sol";

contract TokenHandler is Test {
    Token private immutable token;
    address[3] public actors = [address(0xA11CE), address(0xB0B), address(0xCA201)];

    constructor(Token token_) {
        token = token_;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 3];
        address to = actors[toSeed % 3];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        address to = actors[toSeed % 3];
        uint256 available = token.balanceOf(owner);
        uint256 allowance = token.allowance(owner, spender);
        amount = bound(amount, 0, available < allowance ? available : allowance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
    }
}

contract TokenInvariantTest is StdInvariant, Test {
    Token private token;
    TokenHandler private handler;

    function setUp() public {
        token = new Token();
        handler = new TokenHandler(token);
        token.transfer(handler.actors(0), 1_000_000_000 ether);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyAndBalancesAreConserved() public view {
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        uint256 sum;
        for (uint256 i; i < 3; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, 1_000_000_000 ether);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }
}
