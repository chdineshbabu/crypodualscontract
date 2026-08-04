# CLAUDE.md — crypodualscontract

Developer context for the Solidity smart-contract suite behind **Crypto Duels**, a
crypto "duels" / ticket-purchase dApp deployed on **Berachain**. This file is for
Claude Code (and humans) picking up the repo cold — read it before editing.

> This is the on-chain half of a larger system. The off-chain app (frontend, admin
> panel, and game/socket backends) lives in the sibling `../crypto_duels` repo and
> consumes the addresses/ABIs produced here. See that repo's own `CLAUDE.md`.

## What this project is

Users buy game **tickets** priced in a base stablecoin (**USDG**). They can pay with
USDG directly, native **ETH** (wrapped as WETH), or other allowlisted ERC-20s.
Non-USDG payments are auto-swapped to USDG via **Uniswap V3** `SwapRouter02` (exact-output).
Ticket proceeds are split between a **team** address, an **admin / OZ-fee** address, and a
**`DuelsVault`** that custodies the pooled base token. Player ticket balances are tracked
on-chain and consumed off-chain by the game backends.

## Tech stack

| Concern      | Choice |
|--------------|--------|
| Framework    | Hardhat `^2.22.18` |
| Deployment   | Hardhat **Ignition** (`@nomicfoundation/hardhat-ignition` `^0.15.11`) |
| Toolbox      | `@nomicfoundation/hardhat-toolbox` `^5.0.0` |
| Contract libs| OpenZeppelin `contracts` + `contracts-upgradeable`, both `^4.9.3` |
| Solidity     | Dual compilers **0.8.26** and **0.8.22**, `optimizer { runs: 50 }`, `viaIR: true` |
| Secrets      | `dotenv` — deployer key from `process.env.PRIVATE_KEY`; RPCs from `RH_MAINNET_RPC_URL` / `RH_TESTNET_RPC_URL` |

### Networks (`hardhat.config.js`)

> **Migrated to Robinhood Chain (2026-08).** The Berachain networks were replaced.
> The contract *source* is still Uniswap-V2-shaped — the V2-vs-V3 swap-logic decision
> is deferred (see the migration plan); this pass changed only the network/deploy config.

| Network              | Type    | chainId | RPC (public fallback; override via env) |
|----------------------|---------|---------|------------------------------------------|
| `robinhood`          | mainnet | 4663    | https://rpc.mainnet.chain.robinhood.com |
| `robinhood_testnet`  | testnet | 46630   | https://rpc.testnet.chain.robinhood.com |

Native gas token is **ETH**. Public RPCs are rate-limited — set `RH_MAINNET_RPC_URL`
/ `RH_TESTNET_RPC_URL` to your **Dwellir** (or Alchemy) endpoint for real use.
Verification uses **Blockscout** (`robinhoodchain.blockscout.com` /
`explorer.testnet.chain.robinhood.com`), not Etherscan/Routescan. Deployer account is
`[process.env.PRIVATE_KEY]`. **No `.env` is committed** and none should be.

## Directory map

```
contracts/                 # production Solidity (the only compiled code)
  TicketContract.sol       # main app contract — ticket purchase + Uniswap V3 exact-output swaps
  VaultContract.sol        # contract name is `DuelsVault` (see gotcha) — base-token custody
  interfaces/IUniswapV3.sol# V3 SwapRouter02 subset + Chainlink AggregatorV3Interface
  oz/TransparentProxyImports.sol # import-only shim so proxy artifacts compile
  mocks/                   # test-only: MockERC20, MockV3Router (NOT for deployment)
ignition/
  modules/                 # deploy.js, deployVault.js, deployTicket.js
                           # robinhoodDetails.json  — Robinhood Chain params (base/weth/router/quoter/factory)
                           # _details.js            — picks params by --network chainId
                           # bepoliaDetails.json    — OLD Berachain params (now unused; kept for reference)
  deployments/chain-80094/ # recorded Berachain MAINNET deployment (Vault module only) — historical
test/                      # Hardhat/chai tests (TicketContract.test.js)
referance/                 # (sic) legacy/example code — NOT compiled, ignore
data.doc                   # plaintext deployment ledger (addresses per network)
info.json                  # Berachain DEX pool reference metadata (not consumed by contracts)
README.md                  # STALE — unmodified default Hardhat template
```

## Contracts

### `TicketContract.sol` (pragma `^0.8.22`) — main contract, **Uniswap V3**
Upgradeable: `Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable,
PausableUpgradeable`. Uses **SafeERC20**. Constructor `_disableInitializers()`; state
set in `initialize(baseToken, vault, WETH, swapRouter)` where `swapRouter` is the V3
**SwapRouter02**.

- **Economics:** `ticketPrice` (default 1e18 base = USDG), `teamPercentage` (default
  10%, cap 20%), `ozFees` (default 25%), `slippageTolerance` (default 50 bps —
  now **advisory**, the backend uses it to size `amountInMaximum`). `decimals` = 1e18
  scaling constant. All these are set in `initialize` (not inline — inline initializers
  don't run behind a proxy).
- **`purchaseTicket(address _token, uint256 numOfTicket, uint256 amountInMaximum,
  bytes swapPath, uint256 deadline)`** (payable, `whenNotPaused nonReentrant`).
  **EXACT-OUTPUT model** — always delivers exactly `totalAmount` (ticket+team+oz) base:
  - `_token == baseToken`: `safeTransferFrom` the exact `totalAmount`, no swap.
  - `_token == address(0)` (native ETH): `multicall(exactOutput, refundETH)` forwarding
    `amountInMaximum` as value; refunds `msg.value - spent`.
  - allowlisted ERC-20: pull `amountInMaximum`, `exactOutput` for exactly `totalAmount`
    base, refund unspent input.
  Then distributes base to team / vault / admin, bumps `userInfo`, emits `TicketPurchased`.
- **Caller supplies the quote.** V3 `QuoterV2` isn't a `view` fn, so it can't be called
  cheaply on-chain — the **backend** quotes off-chain (QuoterV2 staticcall) and passes
  `amountInMaximum` + the reverse-encoded V3 `swapPath` (`baseToken, fee, …, tokenIn`) +
  `deadline`. **This signature change ripples to the frontend/backend** — see the app
  re-point pass.
- **Hardening:** SafeERC20 (tolerates non-standard/meme ERC-20s); strict allowlist;
  optional **Chainlink** deviation bound via `priceFeeds` + `maxOracleDeviationBps`
  (**off by default** — enable only after testnet validation). ⚠️ **Fee-on-transfer /
  rebasing tokens are NOT supported** by V3 exact-output — don't `addToken` them.
- **Admin (`onlyOwner`):** `addToken`/`removeToken`, `setAdmin`, `setVaultAddress`,
  `setRouterAddress`, `setSlippageTolerance`, `setBaseToken`, `setOZFees`,
  `setTeamPercentage`, `setTicketPrice`, `setPriceFeed`, `setMaxOracleDeviation`,
  `pause`/`unpause`. Has `receive()` (needed for `refundETH`).

### `VaultContract.sol` → contract `DuelsVault`
Upgradeable (same OZ mixins). `initialize(address _baseToken)` sets the custody token
(USDG) and `admin = msg.sender`; reverts on a zero token. Uses **SafeERC20**.
- `deposit(amount)` — anyone, `whenNotPaused nonReentrant`.
- `withdraw(user, amount)` — **`onlyAdmin`** (distinct from owner!), `whenNotPaused
  nonReentrant`; rejects the zero recipient.
- `vaultBalance()` view; `setBaseToken` (rejects a token switch while a balance remains),
  `setAdmin` (both `onlyOwner`), `setPaused(bool)`.
- The custody token variable is `baseToken` (renamed from the old `honeyToken`).
- **Dual-authority model:** `onlyOwner` for config vs custom `onlyAdmin` for
  withdrawals — owner and admin are different roles. (Set the vault `admin` to the
  game-backend signer post-deploy.)

### ~~`SwapQuoteQuery.sol`~~ — REMOVED
The V2 quote oracle was deleted in the V3 migration. V3 quoting is done **off-chain**
by the backend via Uniswap's own **QuoterV2**
(`0x33e885ed0ec9bf04ecfb19341582aadcb4c8a9e7`, in `robinhoodDetails.json`). The
`interfaces/IUniswapV2.sol` and `deploySwapQuote.js` were removed with it.

## Commands

`package.json` has **no scripts** — use the Hardhat CLI directly:

```bash
npx hardhat compile
npx hardhat test          # test/TicketContract.test.js — 8 passing (base + ERC20 + native-ETH swap paths, guards)
                          # (use ./node_modules/.bin/hardhat if npx pulls a newer global hardhat)
npx hardhat node          # local chain
```

Deploy via Ignition (per module):

```bash
# full stack: ProxyAdmin + DuelsVault + TicketContract behind transparent proxies
npx hardhat ignition deploy ./ignition/modules/deploy.js --network robinhood

# individual modules
npx hardhat ignition deploy ./ignition/modules/deployVault.js --network robinhood   # vault only
npx hardhat ignition deploy ./ignition/modules/deployTicket.js --network robinhood   # ticket only (needs details.vault)

# post-deploy owner config (team/admin/allowlist/vault-admin) — see scripts/configure.js header
TICKET_ADDRESS=0x.. VAULT_ADDRESS=0x.. TEAM_ADDRESS=0x.. ADMIN_ADDRESS=0x.. VAULT_ADMIN=0x.. \
  npx hardhat run scripts/configure.js --network robinhood

# verify on Blockscout after deploy
npx hardhat verify --network robinhood <address> <constructor-args...>
```

Requires `PRIVATE_KEY` in `.env`. `_details.js` auto-selects mainnet vs testnet
addresses from the `--network` chainId (4663 → mainnet, 46630 → testnet), and now
**defaults to mainnet** params for any other network. The `deploy.js` / `deployVault.js`
modules use the **Transparent Upgradeable Proxy + ProxyAdmin** pattern and initialize each
proxy **atomically in its constructor** (no front-runnable window).

> **Testnet params are placeholders.** `robinhoodDetails.json`'s `testnet` section is
> zero-addresses (Robinhood Chain testnet USDG/WETH/router aren't published yet). Fill
> them from the testnet Blockscout before deploying to `robinhood_testnet`, or the
> deploy will revert at `initialize`. Mainnet params are complete (USDG/WETH/V2 router).

## Deployed addresses

> ⚠️ **These are the OLD Berachain deployments** (historical). No Robinhood Chain
> deployment exists yet — this migration pass changed config only. Record new
> Robinhood addresses in `data.doc` after deploying. Robinhood Chain **ecosystem**
> addresses (USDG/WETH/V2 router) live in `ignition/modules/robinhoodDetails.json`.

**Berachain mainnet (chainId 80094)** — from `data.doc`:
- TicketContract: `0x97989FBbB08b9f51225db1019534e4F0Fdf054ef`
- VaultContract: `0xfb39394CA78d04AE4bEEda0971B79996B991D518`
- SwapQuoteQuery: `0x2a8DC049A1D9378628e374E24ADd381d85F576c6`
- HONEY (base token): `0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce`
- "New Vault": `0x1fF00B0788Fe5B68D4752fF1062e3636B6e5a99B`

**Mainnet Ignition record** (`ignition/deployments/chain-80094/`): VaultProxyAdmin
`0x5AA2f7506952a612064B4dfc84BD7c843c5b6Bc3`, HoneyVaultImplementation
`0xB3728CC37AF0dE723B686Bf64937A26d5c6d8260`, HoneyVaultProxy
`0xb0B6B80bE59a98722c9988FA3aaF551684Be7603`.

**Bepolia testnet (chainId 80069)** — from `data.doc`: Ticket
`0x8021b3A43d9e3b213E908ea3960B4C0C5E22EBE2`, proxy Ticket
`0x20Ba8612Bf8Ef00774f807b3D9e24c40A205C4fE`, Vault
`0x42F945224afEA1019ADF1d7Be020450f4Df529C7`, SwapQuoteQuery
`0x409dD95463CBdc9F19FEea04da6fbA82fD15370e`, Honey
`0x4D539677d52dac89e59365E9F78AB55f935E80C6`.

> The off-chain backends currently point at the **proxy Ticket**
> `0x20Ba86…C4fE` and proxy vault `0xb0B6…7603` (testnet) — keep those in sync when
> redeploying. See `../crypto_duels/*/blockchainConfig/config.js`.

## Gotchas & conventions

- **Reference contracts by name, not filename.** `VaultContract.sol` defines
  `DuelsVault` (renamed from `HoneyVault`); some old files/ledgers call things "TokenSwapper".
- **`referance/` is not compiled** (misspelled dir; imports resolve outside the
  tree). It's legacy/example code (old NFT-tier minter, a PriceOracle) — ignore it.
- **Ignition modules (all proxy-based now):** `deploy.js` = full fresh stack (ProxyAdmin
  + DuelsVault + TicketContract + initializers). `deployVault.js` = vault-only.
  `deployTicket.js` = ticket-only behind a proxy against an existing `details.vault`
  (set a real vault in `robinhoodDetails.json` first). The old broken constructor-args
  `deployTicket.js` and the `deploySwapQuote.js` module were fixed/removed in the V3
  migration.
- **Post-deploy:** run `scripts/configure.js` (owner setters + allowlist + vault admin);
  record addresses in `DEPLOYMENTS.md`.
- **DEX assumption:** all pricing/swaps assume a UniswapV2-compatible router (now the
  Uniswap **V2 router on Robinhood Chain**), with WETH as the intermediary hop.
  `address(0)` is the native-ETH sentinel throughout. Whether to move to Uniswap **V3**
  is a deferred decision — see the migration plan.
- **`decimals = 10**18`** is used as a scaling constant, not an ERC-20 `decimals()`
  read.
- **Dead config:** `package.json` exports `./pathFinder` and depends on `ngraph.*`,
  but there is no `pathFinder/` dir. README is the default Hardhat template. No
  tests exist.
- **Never commit** `.env` or the `PRIVATE_KEY`. `.gitignore` already excludes `.env`,
  `node_modules`, `cache`, `artifacts`, typechain, coverage.
