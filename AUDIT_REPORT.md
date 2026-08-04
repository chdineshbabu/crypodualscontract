# Security Audit Report — Crypto Duels Contracts

**Scope:** `contracts/TicketContract.sol`, `contracts/VaultContract.sol` (`DuelsVault`), `contracts/interfaces/IUniswapV3.sol`, deployment modules (`ignition/`), and `scripts/configure.js`.
**Target chain:** Robinhood Chain (Arbitrum-style L2, chainId 4663 / testnet 46630).
**Compiler:** Solidity `^0.8.22` (dual 0.8.22 / 0.8.26, `optimizer runs: 50`, `viaIR: true`).
**Libraries:** OpenZeppelin `contracts` 4.9.3 / `contracts-upgradeable` 4.9.6 (Transparent Proxy + ProxyAdmin).
**Date:** 2026-08-03
**Build status:** compiles clean; 8/8 unit tests pass.

> **Note:** `mocks/*` and `referance/` are test-only / not compiled for deployment and were reviewed only for context.

---

## Summary of findings

| ID | Title | Severity | Status |
|----|-------|----------|--------|
| H-1 | Vault funds fully drainable by a single `admin` key (no timelock/multisig/limits) | **High** | **Accepted risk** (owner elected to keep) |
| H-2 | Upgradeable proxies + single-key `ProxyAdmin`/owner → arbitrary logic replacement (rug) | **High** | Operational — move to multisig/timelock at deploy (guidance added to README) |
| M-1 | Chainlink oracle bound lacks staleness / round-completeness checks | Medium | **Fixed** |
| M-2 | Proxy initializer is front-runnable (uninitialized-proxy window in Ignition deploy) | Medium | **Fixed** |
| M-3 | Missing storage `__gap` in upgradeable contracts | Medium | **Fixed** |
| L-1 | `initialize` does not validate `_valutAddress != address(0)` | Low | **Fixed** |
| L-2 | `msg.value` neither rejected nor refunded on base-token / ERC-20 paths (stuck ETH) | Low | **Fixed** |
| L-3 | No rescue/sweep for assets accidentally sent to `TicketContract` | Low | **Fixed** |
| L-4 | Vault: raw ERC-20 calls, no per-user accounting, `setBaseToken` can strand funds | Low | **Fixed** (SafeERC20 + strand guard; off-chain accounting is by design) |
| L-5 | `setTicketPrice` updates `teamPercentage` but not `ozFees` (fee drift) | Low | **Fixed** |
| I-1 | `slippageTolerance` stored but unused on-chain | Info | Acknowledged (advisory by design; kept for the backend/API) |
| I-2 | Fractional-ticket rounding credits full `numOfTicket` while payment truncates | Info | Acknowledged (dust; negligible) |
| I-3 | Full trust in backend-supplied `swapPath` / `amountInMaximum` | Info | Acknowledged (inherent to the V3 off-chain-quote design; no protocol loss) |
| I-4 | Floating pragma; `optimizer runs: 50` | Info | Acknowledged (dual-compiler config is intentional) |
| I-5 | Stale README, dead `pathFinder` export & `ngraph` deps, testnet placeholder addresses | Info | **Fixed** (README + package.json cleaned; testnet addresses are a deliberate deploy-time revert) |
| I-6 | Vault `deposit`/`withdraw` not `nonReentrant` | Info | **Fixed** |

No **Critical** issues (directly exploitable, unconditional theft by an arbitrary caller) were found. The exact-output payment design is sound and protects protocol proceeds; the dominant risks are **centralization / key-management** (H-1, H-2).

> **Remediation status (2026-08-03):** all Medium and Low findings fixed in code, plus I-5/I-6.
> H-1 accepted by the owner; H-2 is an operational step for deploy time. Test suite expanded
> from 8 to **21 passing** (added `msg.value` guards, rescue, zero-vault init, oracle
> staleness/round, and a full `DuelsVault` suite). See "Remediation applied" at the end.

---

## High

### H-1 — Vault funds fully drainable by a single `admin` key
**File:** `contracts/VaultContract.sol:66`

```solidity
function withdraw(address user, uint256 amount) external onlyAdmin whenNotPaused {
    uint256 balance = baseToken.balanceOf(address(this));
    require(balance >= amount, "Not enough balance in the vault");
    bool success = baseToken.transfer(user, amount);
    ...
}
```

`DuelsVault` custodies the pooled "ticket portion" of every purchase (`TicketContract` transfers `ticketAmount` to `valutAddress` on each buy — `TicketContract.sol:180`). Withdrawals are gated only by `onlyAdmin`, where `admin` is a single address (per `CLAUDE.md`, the game-backend signer). That one key can move **any amount to any address at any time**. There is no timelock, no multisig, no per-tx or rate limit, and no on-chain accounting tying withdrawals to legitimate game payouts.

**Impact:** Compromise (or misuse) of the backend signer key = total loss of all pooled player funds.

**Recommendation:**
- Make `admin` a multisig (e.g. Safe) and/or route withdrawals through a timelock.
- Consider a daily withdrawal cap / rate-limit enforced on-chain.
- Keep the vault paused-by-owner as an incident brake (already possible via `setPaused`), and monitor `WithdrawEvent`.

---

### H-2 — Upgradeable proxies controlled by a single deployer-owned `ProxyAdmin`
**Files:** `ignition/modules/deploy.js:7`, `deployTicket.js:12`, `deployVault.js`

Both contracts sit behind Transparent Upgradeable Proxies whose `ProxyAdmin` is owned by `m.getAccount(0)` (the deployer EOA). Additionally the implementations' `owner` = deployer. The upgrade authority can replace either contract's logic with **arbitrary code** — including a version that drains the vault or redirects all proceeds — with no delay or user opt-out. The same actor also controls every economic setter (`setVaultAddress`, `setTeamAddress`, `setAdmin`, `setTicketPrice`, `setRouterAddress`).

**Impact:** A single compromised/malicious key can rug all funds and all future proceeds.

**Recommendation:**
- Transfer `ProxyAdmin` ownership and contract `owner` to a multisig, ideally behind a timelock, before any real funds flow.
- Document the upgrade policy publicly.
- Longer term, consider making the vault non-upgradeable or governance-gated.

---

## Medium

### M-1 — Chainlink oracle bound lacks staleness / round-completeness checks
**File:** `contracts/TicketContract.sol:253-255`

```solidity
(, int256 tp, , , ) = AggregatorV3Interface(tf).latestRoundData();
(, int256 bp, , , ) = AggregatorV3Interface(bf).latestRoundData();
require(tp > 0 && bp > 0, "Bad oracle price");
```

The optional anti-manipulation bound reads `latestRoundData()` but **discards `updatedAt` and `answeredInRound`**. A stale-but-positive price would pass `> 0`, so the deviation check can validate against outdated data. This is the exact mechanism meant to *catch* manipulation, so a silent staleness failure gives false confidence.

**Impact:** When the feature is enabled (`maxOracleDeviationBps > 0`), the protection can be bypassed under feed staleness/outage. Currently **off by default**, which is why this is Medium rather than High.

**Recommendation:** capture `updatedAt`/`answeredInRound` and `require(updatedAt != 0 && block.timestamp - updatedAt <= maxStaleness && answeredInRound >= roundId);`. Make `maxStaleness` a per-feed configurable value. Validate on testnet before enabling on mainnet.

### M-2 — Proxy initializer is front-runnable (uninitialized-proxy window)
**Files:** `ignition/modules/deploy.js:28-54`, `deployTicket.js:24-36`

The proxies are deployed with empty init data (`"0x"`) and `initialize(...)` is invoked in a **separate** transaction (`m.call(..., "initialize", ...)`). Between proxy creation and that call, the proxy is live but uninitialized; because `initialize` only checks the `initializer` flag, **any caller** can invoke it first and become `owner`/`admin`/`teamAddress`. `_disableInitializers()` in the constructor protects the *implementation*, not the *proxy*.

Robinhood Chain's single-sequencer / no-public-mempool model **reduces** practical exploitability (ordinary users can't easily reorder the sequencer's FIFO), which is why this is Medium — but the pattern is fragile, and the legitimate `initialize` would revert if front-run, at minimum causing a confusing failed deploy.

Note: the **test** harness does it the safe way (`Proxy.deploy(impl, admin, initData)` — `test/TicketContract.test.js:50`); the **Ignition** modules do not.

**Recommendation:** deploy each proxy with the ABI-encoded `initialize` calldata as the proxy constructor's third argument so deployment + initialization are atomic. Verify `owner`/`admin` immediately post-deploy in `configure.js`.

### M-3 — Missing storage `__gap` in upgradeable contracts
**Files:** `contracts/TicketContract.sol`, `contracts/VaultContract.sol`

Neither upgradeable contract reserves a trailing `uint256[N] private __gap;`. Appending new state variables in a future upgrade is safe for these leaf contracts today, but a `__gap` is the standard guard against layout mistakes (e.g. inserting a new base contract) and is expected for OZ-upgradeable code.

**Recommendation:** add a `__gap` to each. If you use the OZ Upgrades plugin/validation, wire it into the deploy/upgrade flow to catch layout regressions automatically.

---

## Low

### L-1 — `initialize` doesn't validate `_valutAddress`
**File:** `contracts/TicketContract.sol:103-105, 119`

`_baseToken`, `_WETH`, `_swapRouter` are zero-checked; `_valutAddress` is not. A zero vault makes every purchase revert at `safeTransfer(valutAddress, ticketAmount)` (DoS until `setVaultAddress` is called). Recoverable, but a deploy-time footgun.
**Fix:** `require(_valutAddress != address(0), "Invalid vault");`

### L-2 — `msg.value` not handled on non-ETH paths
**File:** `contracts/TicketContract.sol:154, 164`

On the base-token and ERC-20 branches, any ETH sent with the call is neither used nor refunded — it accumulates in the contract (only `refundAmount`, which stays `0` on these paths, is returned).
**Fix:** `require(msg.value == 0, "No ETH expected")` on the non-ETH branches.

### L-3 — No rescue function for stranded assets
**File:** `contracts/TicketContract.sol` (has `receive()` at :370, no sweep)

ETH (via `receive()`) or tokens sent directly to the contract are permanently stuck. Consider an `onlyOwner` `rescue(token, to, amount)` (guarding against draining in-flight balances — the contract is designed to hold ~0 between txs).

### L-4 — Vault: raw ERC-20, no per-user accounting, token-switch stranding
**File:** `contracts/VaultContract.sol:56, 69, 88`

- Uses raw `transfer`/`transferFrom` + `require(success)` instead of `SafeERC20` (inconsistent with `TicketContract`; brittle for non-standard tokens).
- `deposit` records no per-user balance — all accounting is off-chain, so the on-chain contract cannot itself attribute funds (reinforces H-1's trust model).
- `setBaseToken` (`onlyOwner`) swaps the custody token; any previously deposited token becomes stranded (no path to withdraw the old token).
**Fix:** adopt `SafeERC20`; forbid or carefully gate `setBaseToken` once funded; document the off-chain accounting invariant.

### L-5 — `setTicketPrice` updates team cut but not oz fee
**File:** `contracts/TicketContract.sol:339-344` (vs `setOZFees` :321)

`setTicketPrice` recomputes `teamPercentage` as 10% of the new price but leaves `ozFees` untouched (it's a flat amount relative to one base unit, not the ticket price). This may be intended, but the asymmetry is easy to misconfigure — after a price change the oz fee no longer tracks the price. Document the intent or recompute both consistently.

---

## Informational

- **I-1** `slippageTolerance` (`:57`, setter `:306`) is stored and validated but never used on-chain — purely advisory for the backend. Consider a NatSpec note or removal to avoid implying on-chain enforcement.
- **I-2** `purchaseTicket` credits `userInfo.ticketBalance += numOfTicket` (full 1e18-scaled value) while payment amounts truncate via integer division (`:146-149`). The free dust is ~1e-18 of a ticket and economically irrelevant, but confirm the backend interprets `ticketBalance` as `value / 1e18`.
- **I-3** The contract fully trusts the caller-supplied `swapPath` and `amountInMaximum` (`:169`, `:206`). A malformed path simply reverts (no protocol loss — exact-output always yields `totalAmount` base or the tx reverts), and a caller can only overpay their own input. The oracle bound (M-1) is the only on-chain price sanity check; keep it enabled in production once hardened.
- **I-4** Floating pragma `^0.8.22` and `optimizer runs: 50`. Pin an exact compiler for deployment reproducibility; the low `runs` favors deploy size over call gas (fine for infrequent calls).
- **I-5** `README.md` is the default Hardhat template; `package.json` exports `./pathFinder` and depends on `ngraph.*` with no `pathFinder/` dir; `robinhoodDetails.json` testnet section is all-zero placeholders (intended to revert `initialize`). Clean up dead config before mainnet.
- **I-6** Vault `deposit`/`withdraw` inherit `ReentrancyGuard` but aren't marked `nonReentrant`. Safe for standard ERC-20s (no callbacks; no cross-function invariant to break since there's no internal ledger); add the modifier if a hook-bearing token could ever be the custody asset.

---

## What the code does well

- **Exact-output model** guarantees the protocol always receives exactly `totalAmount` base regardless of swap price — users can only ever overpay their *own* input, never shortchange the protocol.
- `SafeERC20` throughout `TicketContract`, with `forceApprove(router, max)` → swap → `forceApprove(router, 0)` allowance hygiene (`:205-215`).
- Correct **CEI ordering** + `nonReentrant` + `whenNotPaused`; ETH refund is the last action and its math is sound (contract never refunds more than the caller's own net, never touches pre-existing balances).
- Caller-enforced `deadline` compensates for SwapRouter02 dropping the `deadline` param.
- Strict allowlist; base token cannot be re-added; `_disableInitializers()` in both constructors.
- Decimals-aware `baseUnit = 10**decimals()` so economics are correct for a 6-decimal base (USDG).
- No committed secrets; `.env` is gitignored.

---

## Remediation priority

1. **Before any mainnet funds:** move `ProxyAdmin` owner, contract `owner`, and vault `admin` to a multisig (+timelock) — addresses **H-1** and **H-2**, the only findings that risk total loss.
2. Make proxy init atomic (**M-2**) and add `__gap`s (**M-3**) — cheap, do them in the same pass.
3. Harden the oracle bound (**M-1**) and enable it on mainnet after testnet validation.
4. Sweep up the Lows (**L-1**, **L-2**, **L-4**) and the dead config before verification/handoff.

---

## Remediation applied (2026-08-03)

Fixes for every Medium/Low (and I-5/I-6) were implemented. H-1 was accepted by the owner and
left as-is; H-2 remains an operational deploy-time action. Build compiles clean; **21/21**
tests pass.

**`contracts/TicketContract.sol`**
- **M-1** — `_requireOracleBound` now reads `roundId`/`updatedAt`/`answeredInRound`, requires
  `answeredInRound >= roundId` ("Stale oracle round") and `updatedAt` within a configurable
  `maxOracleStaleness` ("Oracle price too old"). New `maxOracleStaleness` state var (default
  `3600`, set in `initialize`) + `setMaxOracleStaleness` owner setter + event.
- **M-3** — added `uint256[50] private __gap;`.
- **L-1** — `initialize` now `require(_valutAddress != address(0), "Invalid vault")`.
- **L-2** — base-token and ERC-20 branches now `require(msg.value == 0, "No ETH expected")`.
- **L-3** — added `rescueERC20(token,to,amount)` and `rescueETH(to,amount)` (owner-only, with events).
- **L-5** — `setTicketPrice` now also resets `ozFees` to 25% of the new price (matching `initialize`).

**`contracts/VaultContract.sol` (`DuelsVault`)**
- **L-4** — adopted `SafeERC20` for `deposit`/`withdraw`; `setBaseToken` now requires the
  current-token balance to be zero ("Withdraw current token first") to prevent stranding;
  `withdraw` rejects the zero recipient. (On-chain per-user accounting remains intentionally
  off-chain — this is the documented trust model, tied to H-1.)
- **I-6** — `deposit`/`withdraw` marked `nonReentrant`.
- **M-3** — added `uint256[50] private __gap;`.

**`ignition/modules/*` (M-2)**
- `deploy.js`, `deployVault.js`, `deployTicket.js` now initialize each proxy **atomically** by
  passing `m.encodeFunctionCall(impl, "initialize", [...])` as the proxy constructor's `_data`,
  eliminating the uninitialized-proxy front-run window. Verified end-to-end (vault deploys +
  initializes on the in-process network).

**Cleanup (I-5)**
- `package.json` — removed the dead `./pathFinder` export and unused `ngraph.*` deps.
- `README.md` — replaced the default Hardhat template with accurate project docs (incl. the
  H-1/H-2 multisig note).

**Tests (`test/`)**
- `TicketContract.test.js` — added coverage for the `msg.value` guards, ERC-20/ETH rescue,
  zero-vault `initialize` revert, and the oracle bound (fresh-passes / stale-reverts /
  incomplete-round-reverts) via a new `MockAggregator`.
- `DuelsVault.test.js` — new suite: SafeERC20 deposit/withdraw, `onlyAdmin`, zero-recipient
  guard, the `setBaseToken` strand guard, and pause behavior.
- `contracts/mocks/MockAggregator.sol` — new test-only Chainlink stand-in.

### Still outstanding (by design / for the owner)
- **H-1** (accepted): the vault `admin` key can still move all pooled funds. Mitigate
  operationally — make `admin` a multisig, monitor `WithdrawEvent`, keep pause ready.
- **H-2** (operational): transfer `ProxyAdmin` ownership + each contract `owner` to a
  multisig/timelock immediately after deploy, before funds flow.
- **I-1 – I-4** (acknowledged): no action — advisory field kept for the backend, negligible
  rounding dust, inherent backend-quote trust, and the intentional dual-compiler config.
