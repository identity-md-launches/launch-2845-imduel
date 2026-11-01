# IMDuel token test coverage

The original tests remain intact. `IMDuelToken.Properties.t.sol` adds regression and
fuzz tests, and `IMDuelToken.Invariant.t.sol` targets the actions in
`handlers/IMDuelTokenHandler.sol`. All dependencies are already vendored in the
project; these tests use no RPC, environment-dependent addresses, FFI or downloads.

## Property selection

The five discovery perspectives in the supplied Pashov reference were reviewed
against `src/IMDuelToken.sol`. The Trail of Bits reference informed input generation,
edge cases and checks against vacuous properties. The following are properties of
this fixed-supply token, with no assumptions about exchange prices or vault shares.

| Perspective | Relevant implementation | Property checked |
| --- | --- | --- |
| Conservation | Constructor (lines 70–72), transfer accounting (140–153) | The sum of every reachable holder's balance is exactly `1_000_000_000 * 10**18`; each holder's balance plus cumulative outgoing transfers equals cumulative incoming transfers, including its initial allocation. |
| State transitions | `approve`, `transferFrom`, `_spendAllowance` (122–133, 156–169) | Approvals replace a grant. Finite allowances equal the latest grant minus cumulative spending. Unlimited allowances persist until replaced. Unrelated approvals and balances remain unchanged. |
| Round trips | `_transfer` (140–153) | Transferring out and back restores both holders exactly, including repeated cycles and single-wei values. Splitting an amount between two transfers gives the same balances as one transfer. |
| Adversarial inputs | Guards (141–145, 157–158, 166) | Invalid addresses, excessive balances, excessive allowances and revoked authorization are rejected with the specific error. Failed delegated transfers restore the allowance and can be retried after correcting the input or funding the owner. |
| Token-specific behavior | Metadata, constructor, ERC-20 entry points (70–133) | Exact name, symbol, decimals and fixed supply; zero-value events; self-transfers; caller/owner/recipient aliasing; no cross-owner or reversed-allowance authorization. |

## Stateful harness boundaries

Five accounts can send tokens: the deploying handler and four test actors. Each
starts funded through real transfers. The token contract is a sixth, recipient-only
account, so transfers to it remain included in conservation without inventing a
transaction originating from the token. No token storage or balance is edited with
cheatcodes. The zero address is used solely to exercise rejected operations.

Only the twelve action selectors are targeted. Success paths use bounded amounts
with explicit zero, one-wei and full-balance cases. Approvals also include maximum
and maximum-minus-one values. Separate failure actions reach balance, allowance and
address guards. Expected failures are checked through low-level calls; any unexpected
revert or assertion failure fails the campaign. The ghost ledger changes only for
successful calls, and every owner/spender pair is checked for allowance isolation.

The inline settings request 1,000 cases per new fuzz property and 256 invariant
sequences of depth 128 per invariant, with `fail-on-revert` enabled. The suite adds
no configuration file changes. The protected launch harness supplied with the task
belongs to the external verifier; the local tests exercise this repository's token
and do not claim to reproduce the external PoolManager integration.

## Reproduction

From the repository root, keep generated artifacts in the disposable scratch area:

```sh
FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache forge build
FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache FOUNDRY_FUZZ_SEED=0x1d1b9f71ba445966e9fa935492eb04cfbad5aba79f975bbbc353f356ecdd8a74 forge test
```

Nothing outside `test/scratch/` depends on scratch contents. That directory can be
deleted before building or running the delivered tests.
