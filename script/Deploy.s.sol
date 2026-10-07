// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {Token} from "../src/Token.sol";

/// @notice Direct deployment helper. Factory launches use Token's creation code directly.
contract Deploy is Script {
    error UnsupportedChain(uint256 chainId);
    error UnexpectedChain(uint256 expected, uint256 actual);

    function run() external returns (Token token) {
        return deploy(vm.envOr("EXPECTED_CHAIN_ID", uint256(0)));
    }

    /// @dev Zero means a local simulation on 31337 only. Tests pass configuration directly.
    function deploy(uint256 expectedChainId) public returns (Token token) {
        if (block.chainid != 31337 && block.chainid != 11155111) {
            revert UnsupportedChain(block.chainid);
        }
        if (expectedChainId != block.chainid && !(expectedChainId == 0 && block.chainid == 31337)) {
            revert UnexpectedChain(expectedChainId, block.chainid);
        }

        vm.startBroadcast();
        token = new Token();
        vm.stopBroadcast();
    }
}
