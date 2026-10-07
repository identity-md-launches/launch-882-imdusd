# imdUSD (IMDUSD)

A fixed-supply ERC-20 implemented in `src/Token.sol:Token`, using locally vendored
OpenZeppelin ERC20. The constructor has **no arguments** and is not payable.

| Parameter | Value |
| --- | --- |
| Name | `imdUSD` |
| Symbol | `IMDUSD` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Base-unit supply | `1000000000000000000000000000` (`10^27`) |
| Initial recipient | Constructor `msg.sender` |
| Default launch target | Sepolia (`11155111`) |

## Behavior and assumptions

The complete supply is minted exactly once, in the constructor. A factory that
deploys the token receives all of it; the factory's caller does not. A direct
deployment assigns the supply to the deploying account. There is no owner,
external mint or burn function, pause, blacklist, tax, transfer limit, rebase,
upgrade mechanism, or initialization step. There are no external calls in token
operations and no address-specific exemptions. Transfers deliver the exact amount.

`imdUSD` is the requested name; this contract implements no dollar peg, reserve,
collateral, redemption, yield, or price oracle. Those features were not requested.
The contract does not itself allocate launch shares or create a liquidity pool.
The network's launch factory handles distribution and liquidity separately.

The ERC-20 interface consists of `name`, `symbol`, `decimals`, `totalSupply`,
`balanceOf`, `allowance`, `transfer`, `approve`, and `transferFrom`, with an
additional `INITIAL_SUPPLY` getter. Successful mutations return `true`; invalid
operations revert with OpenZeppelin's ERC-6093 custom errors. `Transfer` and
`Approval` events follow the vendored implementation: `transferFrom` emits a
`Transfer`, without an `Approval` event when spending allowance.

Zero-value transfers between nonzero accounts and self-transfers are supported.
Transfers to the zero address and approvals to a zero spender revert. Delegated
transfers require sufficient balance and allowance. Finite allowances decrease;
`type(uint256).max` is treated as unlimited and does not decrease. `approve`
replaces the allowance, so applications should account for the standard allowance
replacement race and prefer limited approvals, revoking before changing a live
allowance when appropriate. Failed operations leave balances and allowances intact.

## Offline build and verification

Requires Foundry 1.8.3 and cached Solidity **0.8.26**. All Solidity dependencies are
ordinary files in `lib/`; nothing is downloaded by these commands. The compiler
is pinned by version, optimization is enabled with 200 runs, EVM target is Paris,
and `bytecode_hash = "none"`. FFI and filesystem cheatcode access are disabled.

```sh
forge build --offline
forge test --offline
forge test --offline --fuzz-seed 0x20261007 --fuzz-runs 2048
forge fmt --check
EXPECTED_CHAIN_ID=0 forge script script/Deploy.s.sol:Deploy --offline
```

`forge build` and `forge test` also use the offline setting in `foundry.toml`.
Tests read or set no environment variables and require no RPC or forks. Coverage
includes metadata and mint events, CREATE2 factory ownership and exact token
distribution, transfer and allowance edge cases, unauthorized operations, runtime
opcode restrictions, four fuzz properties, and a stateful supply-conservation
invariant across transfers, approvals, and delegated transfers.

The factory fixture checks the token-side transfer amounts. It does not run a
Uniswap PoolManager or prove live pool seeding/swaps. The supplied protected
launch harness requires the network's launch contracts and resolved deployment
parameters; the network must run that integration check before admission.

## Deployment and operator responsibilities

For the IdentityMD custom launch, the operator uses the creation bytecode of
`src/Token.sol:Token`, constructor arguments `[]`, and the exact supply above.
The launch factory must be the immediate deploying caller. There are no
application contracts to deploy and no post-deployment initialization calls.
Pool configuration, paired currency, price, requester recipient, and economics
were not supplied in this assignment and must come from the approved launch job.
This implementation does not invent a launch manifest or economics.

`script/Deploy.s.sol:Deploy` is a standalone direct-deployment helper, separate
from the factory launch path. It reads only `EXPECTED_CHAIN_ID` and creates
exactly one token between broadcast markers. It accepts only chain `31337` or
`11155111`. An expectation of zero is valid only on local chain `31337`; Sepolia
requires an explicit matching expectation. The script contains no signer or
network credentials. Tests call `deploy(expectedChainId)` directly.

The last verification command above is a local simulation and sends no
transaction. For an independently approved standalone deployment, the following
is an **operator-only template**; the operator's approved runner must supply its
own network and signing configuration outside this repository:

```sh
EXPECTED_CHAIN_ID=11155111 forge script script/Deploy.s.sol:Deploy --offline --broadcast
```

For the network launch, use its factory deployer instead of that direct-deployment
template. After independent review, the operator is responsible for the correct
chain, factory, recipient and launch parameters, broadcasting, verifying deployed
bytecode and metadata, and confirming the full constructor mint in the receipt.
There are no administrative keys or recurring maintenance calls for the token.
Holders control their balances and approvals. There is no recovery function for
tokens sent to an incorrect or inaccessible address, including this token contract.
Direct Ether payments revert; forcibly sent Ether cannot be recovered.

See `REVIEW.md` for checks performed and review limitations. No transaction has
been broadcast as part of this assignment.
