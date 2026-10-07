// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {Token} from "../src/Token.sol";

/// @dev Local fixture for the launch factory's CREATE2 and distribution behavior.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (Token) {
        return new Token{salt: salt}();
    }

    function move(Token token, address to, uint256 amount) external {
        require(token.transfer(to, amount));
    }
}

/// forge-config: default.fuzz.runs = 1000
contract TokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    Token private token;

    function setUp() public {
        token = new Token();
    }

    function test_metadataAndEntireInitialSupply() public view {
        assertEq(token.name(), "imdUSD");
        assertEq(token.symbol(), "IMDUSD");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_constructorEmitsFullMint() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), address(this), SUPPLY);
        new Token();
    }

    function test_factoryReceivesSupplyAndLaunchTransfersArriveWhole() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        Token launched = factory.deploy(bytes32(uint256(1)));
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);

        address distributor = address(0xD157);
        address poolManager = address(0x9001);
        uint256 swarm = SUPPLY / 10;
        uint256 seed = SUPPLY / 2;
        factory.move(launched, distributor, swarm);
        factory.move(launched, poolManager, seed);
        factory.move(launched, BOB, SUPPLY - swarm - seed);
        assertEq(launched.balanceOf(distributor), swarm);
        assertEq(launched.balanceOf(poolManager), seed);
        assertEq(launched.balanceOf(BOB), SUPPLY - swarm - seed);
        assertEq(launched.balanceOf(address(factory)), 0);

        vm.prank(distributor);
        assertTrue(launched.transfer(ALICE, swarm));
        assertEq(launched.balanceOf(ALICE), swarm);
        assertEq(launched.balanceOf(distributor), 0);

        // Exercise the token legs of a pool buy and sell; no pool implementation is mocked.
        vm.prank(poolManager);
        assertTrue(launched.transfer(ALICE, 100 ether));
        assertEq(launched.balanceOf(ALICE), swarm + 100 ether);
        vm.prank(ALICE);
        assertTrue(launched.transfer(poolManager, 100 ether));
        assertEq(launched.balanceOf(poolManager), seed);
        assertEq(launched.balanceOf(ALICE), swarm);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_transferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 17 ether);
        assertTrue(token.transfer(ALICE, 17 ether));
        assertEq(token.balanceOf(ALICE), 17 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 17 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_fullBalanceTransfer() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_zeroValueTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_oneWeiCanRoundTripWithoutRoundingOrFees() public {
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferRevertsWithInfiniteApproval() public {
        uint256 maximum = type(uint256).max;
        assertTrue(token.approve(SPENDER, maximum));
        bytes memory errorData =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum);
        vm.expectRevert(errorData);
        token.transfer(ALICE, maximum);
        vm.expectRevert(errorData);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, maximum);
        assertEq(token.allowance(address(this), SPENDER), maximum);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferRejectsZeroRecipientEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_emptyHolderCannotTransferPositiveAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_approvalEmitsEventAndCanBeReplacedOrRevoked() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), SPENDER, 20 ether);
        assertTrue(token.approve(SPENDER, 20 ether));
        assertEq(token.allowance(address(this), SPENDER), 20 ether);
        assertTrue(token.approve(SPENDER, 7 ether));
        assertEq(token.allowance(address(this), SPENDER), 7 ether);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approvalRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_zeroApprovalStillRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroCallerCannotTransferOrApprove() public {
        // Exercise zero-address guards directly; this is not a claim that zero can sign transactions.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(ALICE, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(SPENDER, 1);
        assertEq(token.allowance(address(0), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromConsumesFiniteAllowanceAndEmitsTransfer() public {
        token.approve(SPENDER, 20 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 12 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 12 ether));
        assertEq(token.allowance(address(this), SPENDER), 8 ether);
        assertEq(token.balanceOf(ALICE), 12 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 12 ether);
    }

    function test_infiniteAllowanceRemainsUnchanged() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1 ether));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 1 ether);
    }

    function test_largestFiniteAllowanceIsConsumed() public {
        assertTrue(token.approve(SPENDER, type(uint256).max - 1));
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertTrue(token.transferFrom(address(this), BOB, 1));
        vm.stopPrank();
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 3);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_infiniteAllowanceCanBeReducedAndRevoked() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertTrue(token.approve(SPENDER, 2));
        assertEq(token.allowance(address(this), SPENDER), 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 2));
        assertEq(token.allowance(address(this), SPENDER), 0);

        assertTrue(token.approve(SPENDER, type(uint256).max));
        assertTrue(token.approve(SPENDER, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
    }

    function test_fullSupplyDelegatedTransferCannotReuseAllowanceAfterRoundTrip() public {
        assertTrue(token.approve(SPENDER, SUPPLY));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);

        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromToSelfConsumesAllowanceWithoutChangingBalance() public {
        token.approve(SPENDER, 10 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 10 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_unapprovedCallerCannotMoveHolderFunds() public {
        token.transfer(ALICE, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), 100 ether);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_insufficientAllowanceRevertsWithoutChangingState() public {
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 10, 11));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 11);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_insufficientBalanceRollsBackAllowanceSpend() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 100));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 100);
        assertEq(token.allowance(ALICE, SPENDER), 100);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromZeroRecipientRollsBackAllowanceSpend() public {
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferFromRejectsZeroSender() public {
        // OpenZeppelin validates the allowance owner before reaching the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_noMintBurnFreezeOrUpgradeEntryPoints() public {
        token.transfer(ALICE, 100 ether);
        string[15] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "pause()",
            "blacklist(address)",
            "freeze(address)",
            "seize(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "setMinter(address)",
            "disableTransfers()"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, 1 ether);
            (bool deployerSucceeded,) = address(token).call(data);
            assertFalse(deployerSucceeded, signatures[i]);
            vm.prank(BOB);
            (bool strangerSucceeded,) = address(token).call(data);
            assertFalse(strangerSucceeded, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(ALICE), 100 ether);
        }
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100 ether));
        assertEq(token.balanceOf(BOB), 100 ether);
    }

    function test_directEtherPaymentReverts() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
    }

    function test_runtimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff);
        }
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 rawAmount) public {
        // Keep every fuzz run useful; self-transfers and zero recipients have dedicated tests.
        if (recipient == address(0) || recipient == address(this)) recipient = ALICE;
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_overdrawReverts(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedTransferConservesSupply(uint256 rawApproval, uint256 rawAmount) public {
        uint256 approved = bound(rawApproval, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, approved);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), approved - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_allowanceCannotBeExceeded(uint256 rawApproval) public {
        uint256 approved = bound(rawApproval, 0, SUPPLY - 1);
        token.approve(SPENDER, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, approved + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, approved + 1);
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testFuzz_partialSpendsExhaustExactlyOneApproval(uint256 rawApproval, uint256 rawFirstSpend) public {
        uint256 approved = bound(rawApproval, 1, SUPPLY);
        uint256 first = bound(rawFirstSpend, 0, approved);
        assertTrue(token.approve(SPENDER, approved));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, first));
        assertEq(token.allowance(address(this), SPENDER), approved - first);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, approved - first));
        assertEq(token.allowance(address(this), SPENDER), 0);

        // Replenishing a balance must not restore an already-spent authorization.
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), first));
        vm.prank(BOB);
        assertTrue(token.transfer(address(this), approved - first));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedOverdrawIsAtomic(uint256 rawBalance, uint256 rawAmount) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        assertTrue(token.transfer(ALICE, balance));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, amount));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.allowance(ALICE, SPENDER), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalsAreIsolatedByOwnerAndSpender(uint256 approved, uint256 otherApproved) public {
        assertTrue(token.approve(SPENDER, approved));
        assertTrue(token.approve(BOB, otherApproved));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, otherApproved));

        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.allowance(address(this), BOB), otherApproved);
        assertEq(token.allowance(ALICE, SPENDER), otherApproved);
        assertEq(token.allowance(SPENDER, address(this)), 0);
        assertEq(token.allowance(ALICE, BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);

        // Direct transfers change balances without consuming or creating any allowance.
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.allowance(address(this), BOB), otherApproved);
        assertEq(token.allowance(ALICE, SPENDER), otherApproved);
        assertEq(token.allowance(ALICE, BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
