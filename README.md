# IMDuel (IMDUEL)

A fixed-supply ERC-20 token for an IdentityMD custom token launch on Ethereum.

| Field | Value |
| --- | --- |
| Solidity contract | `IMDuelToken` (`src/IMDuelToken.sol`) |
| `name()` | `IMDuel` |
| `symbol()` | `IMDUEL` |
| `decimals()` | `18` |
| `totalSupply()` | `1_000_000_000 * 10**18` = `1000000000000000000000000000` minor units |
| Constructor arguments | none |
| Minted to | `msg.sender` of the constructor, once, in full |
| Owner / admin | none |

## What the contract does

- The constructor credits the whole supply to `msg.sender` and emits `Transfer(0x0, msg.sender, supply)`.
  No further mint path exists: `totalSupply()` is a compile-time constant and nothing writes to it.
- Standard EIP-20 surface: `transfer`, `approve`, `transferFrom`, `balanceOf`, `allowance`, plus the
  metadata views `name`, `symbol`, `decimals`, `totalSupply`.
- `transferFrom` spends only the allowance that `from` granted to `msg.sender`. An allowance of
  `type(uint256).max` is unlimited and is never decremented.
- Transfers to or from the zero address, approvals of the zero spender, and amounts above the
  balance or allowance revert with typed custom errors (`InsufficientBalance`,
  `InsufficientAllowance`, `InvalidReceiver`, `InvalidSender`, `InvalidApprover`, `InvalidSpender`).
- No fee, no burn, no tax, no reflections, no pause, no blocklist, no freeze, no owner, no upgrade
  path, no `receive` or `fallback` (ether sent to it reverts).
- The implementation is self-contained: no external libraries, no `delegatecall`, no `callcode`,
  no `selfdestruct`. The project vendors `forge-std` for tests only.

## Assumptions

- **The deployer receives everything.** The brief says the supply is minted once to the deployer.
  In the IdentityMD launch the deployer is `ProjectFactory.launchCustom`, so the factory holds the
  supply and distributes it (10% to the launch's MerkleDistributor, 80% to the Uniswap v4 pool,
  10% to `economics.remainderTo`). The token itself does none of this and takes no launch addresses,
  because with no fee on any transfer there is nothing to exempt.
- **No administrative powers.** The brief asks for none, so none were added. There is no owner to
  set and nothing to configure after launch.
- **Allowance semantics.** `approve` overwrites the previous allowance (plain EIP-20). The known
  approve front-running caveat applies: set an allowance to zero before changing it to a new
  non-zero value if the spender is untrusted. No `increaseAllowance`/`decreaseAllowance` helpers
  are provided, matching OpenZeppelin v5.
- **No EIP-2612 permit.** Not requested. Gasless approvals would need a separate contract or a new
  token.

## Deployment parameters

The token takes no constructor arguments. Compiler settings are pinned in `foundry.toml`:

| Setting | Value |
| --- | --- |
| `solc` | `0.8.26` |
| `evm_version` | `cancun` |
| `optimizer` | `true`, `optimizer_runs = 200` |
| `bytecode_hash` | `none` (reproducible bytes for the launch comparison) |
| `ffi` | `false`; no `fs_permissions` |

Launch values that are fixed by the launch policy and are not configurable in this repository:

| Launch value | Value |
| --- | --- |
| Chain | Ethereum (chain id 1) |
| Paired currency | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` |
| `pool.fee` | `12500` (1.25%) |
| `pool.tickSpacing` | `60` |
| `economics.poolBps` | `8000` |
| `economics.initialMarketCapWei` | `2500000000000000000000` (2,500 IMD) |
| `economics.remainderTo` | `0xff3e8d9ba776662ca6ed1420ee366afb436d2684` |
| `token.totalSupply` (manifest) | `1000000000000000000000000000` |
| `token.decimals` (manifest) | `18` |

The manifest (`launch.json`) is written by the launch's manifest step after this work is accepted,
not by this repository.

### After launch

Nothing. There is no owner-settable value, no setter and no initialization call. The contract is
final the moment its constructor returns.

### Reference deploy script

`script/DeployIMDuelToken.s.sol` is a reviewable reference for local forks and audits. The launch
does not use it: the factory deploys the token from its creation bytecode. The script reads no
environment variables; `deploy()` is the function tests call directly, and `run()` only wraps it
in a broadcast with whichever signer `forge script` is handed on the command line.

```sh
forge script script/DeployIMDuelToken.s.sol --rpc-url <RPC> --broadcast --sender <ADDR> ...
```

## Operational responsibilities

- **Supply custody.** Whoever deploys holds 100% of the supply at block of deployment. In the
  launch that is the factory, which pays it all out in the same transaction. Outside the launch,
  the deploying key is the sole holder and must protect it like any treasury key.
- **No recovery.** Tokens sent to the zero address are refused, but tokens sent to a wrong
  non-zero address or to a contract without a withdrawal path are lost. The token cannot seize,
  freeze or recover anything, by design.
- **No upgrades.** Any change in behaviour requires a new token and a migration; there is no proxy.
- **Explorer verification.** Verify the source on Etherscan after launch with
  `forge verify-contract` using the pinned compiler settings above (solc 0.8.26, optimizer on,
  200 runs, EVM cancun, no metadata hash). This belongs to the launch's deployer.
- **Allowance hygiene.** Integrators should request exact allowances rather than infinite ones
  where practical. Infinite allowances persist until the holder resets them.

## Security notes

Checked against the pinned eth-security reference:

- Reentrancy: the token makes no external calls, so there is no reentrant path.
- Arbitrary send (`arbitrary-send-erc20`): `transferFrom` only spends `msg.sender`'s own allowance.
- Access control: there are no privileged functions to protect.
- Supply integrity: `totalSupply()` is a constant; balances are only moved, never created or
  destroyed. Balance arithmetic is unchecked only where the preceding check or the fixed total
  supply makes overflow impossible.
- Bytecode: no `delegatecall`, `callcode` or `selfdestruct`, verified by a test that walks the
  reachable runtime opcodes.
- Tools run: `forge build`, `forge test` (including fuzz runs with the verifier's seed) and
  `forge fmt --check`. Slither and Mythril were not available on this machine. Tests passing do
  not constitute an audit.

## Layout

```
foundry.toml                  compiler pins and profile
remappings.txt                forge-std/ -> lib/forge-std/src/
src/IMDuelToken.sol           the token
script/DeployIMDuelToken.s.sol reference deploy script
test/IMDuelToken.t.sol        behaviour, failure and fuzz tests
test/DeployIMDuelToken.t.sol  deploy() test
lib/forge-std/                vendored forge-std v1.9.7 (MIT / Apache-2.0), plain files
```

## Running the checks

```sh
forge build
forge test
forge fmt --check
```

To reproduce the verifier's fuzz run:

```sh
FOUNDRY_FUZZ_SEED=0x1d1b9f71ba445966e9fa935492eb04cfbad5aba79f975bbbc353f356ecdd8a74 forge test
```
