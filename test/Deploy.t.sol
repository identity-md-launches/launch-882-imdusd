// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {Token} from "../src/Token.sol";

contract DeployTest is Test {
    Deploy private deployer;

    function setUp() public {
        deployer = new Deploy();
    }

    function test_localDeploymentWithExplicitChain() public {
        vm.chainId(31337);
        _checkDeployment(31337);
    }

    function test_localDeploymentWithZeroExpectation() public {
        vm.chainId(31337);
        _checkDeployment(0);
    }

    function test_sepoliaDeploymentWithExplicitChain() public {
        vm.chainId(11155111);
        _checkDeployment(11155111);
    }

    function test_rejectsUnsupportedChain() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(Deploy.UnsupportedChain.selector, 1));
        deployer.deploy(1);
    }

    function test_rejectsMismatchedChain() public {
        vm.chainId(31337);
        vm.expectRevert(abi.encodeWithSelector(Deploy.UnexpectedChain.selector, 11155111, 31337));
        deployer.deploy(11155111);
    }

    function test_sepoliaRequiresExplicitExpectation() public {
        vm.chainId(11155111);
        vm.expectRevert(abi.encodeWithSelector(Deploy.UnexpectedChain.selector, 0, 11155111));
        deployer.deploy(0);
    }

    function _checkDeployment(uint256 expectedChainId) private {
        vm.recordLogs();
        Token token = deployer.deploy(expectedChainId);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(token));
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        // Read the actual constructor recipient; no assumption about the script caller.
        address recipient = address(uint160(uint256(logs[0].topics[2])));
        assertTrue(recipient != address(0));
        assertEq(abi.decode(logs[0].data, (uint256)), 1_000_000_000 ether);
        assertEq(token.balanceOf(recipient), 1_000_000_000 ether);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.balanceOf(address(deployer)), 0);
    }
}
