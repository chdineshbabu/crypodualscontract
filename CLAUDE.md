# CLAUDE.md — crypodualscontract

Developer context for the Solidity smart-contract suite behind **Crypto Duels**, a
crypto "duels" / ticket-purchase dApp deployed on **Berachain**. This file is for
Claude Code (and humans) picking up the repo cold — read it before editing.

> This is the on-chain half of a larger system. The off-chain app (frontend, admin
> panel, and game/socket backends) lives in the sibling `../crypto_duels` repo and
> consumes the addresses/ABIs produced here. See that repo's own `CLAUDE.md`.

## What this project is

Users buy game **tickets** priced in a base token (**HONEY**). They can pay with
HONEY directly, native **BERA** (wrapped as WBERA), or other supported ERC-20s.
Non-HONEY payments are auto-swapped to HONEY via a **UniswapV2-compatible router**
(Kodiak on Berachain). Ticket proceeds are split between a **team** address, an
**admin / OZ-fee** address, and a **vault** that custodies pooled HONEY. Player
ticket balances are tracked on-chain and consumed off-chain by the game backends.

## Tech stack

| Concern      | Choice |
|--------------|--------|
| Framework    | Hardhat `^2.22.18` |
| Deployment   | Hardhat **Ignition** (`@nomicfoundation/hardhat-ignition` `^0.15.11`) |
| Toolbox      | `@nomicfoundation/hardhat-toolbox` `^5.0.0` |
| Contract libs| OpenZeppelin `contracts` + `contracts-upgradeable`, both `^4.9.3` |
| Solidity     | Dual compilers **0.8.26** and **0.8.22**, `optimizer { runs: 50 }`, `viaIR: true` |
| Secrets      | `dotenv` — deployer key from `process.env.PRIVATE_KEY` only |

### Networks (`hardhat.config.js`)

| Network              | Type    | chainId | RPC |
|----------------------|---------|---------|-----|
| `berachain`          | mainnet | 80094   | https://rpc.berachain.com |
| `berachain_bepolia`  | testnet | 80069   | https://bepolia.rpc.berachain.com/ |

Verification uses **Routescan** endpoints (no real API key needed). Deployer account
is `[process.env.PRIVATE_KEY]` — a single key, injected via env. **No `.env` is
committed** and none should be.

## Directory map

```
contracts/                 # production Solidity (the only compiled code)
  TicketContract.sol       # main app contract — ticket purchase, pricing, swaps
  VaultContract.sol        # contract name is `HoneyVault` (see gotcha) — HONEY custody
  SwapQuoteQuery.sol       # read-only price/quote oracle (HONEY/WBERA framing)
  interfaces/IUniswapV2.sol# standard UniswapV2 Factory/Pair/Router01/Router02
  oz/TransparentProxyImports.sol # import-only shim so proxy artifacts compile
ignition/
  modules/                 # deploy.js, deployVault.js, deployTicket.js, deploySwapQuote.js
                           # + bepoliaDetails.json (address params)
  deployments/chain-80094/ # recorded MAINNET deployment (Vault module only)
referance/                 # (sic) legacy/example code — NOT compiled, ignore
data.doc                   # plaintext deployment ledger (addresses per network)
info.json                  # Berachain DEX pool reference metadata (not consumed by contracts)
README.md                  # STALE — unmodified default Hardhat template
```

## Contracts

### `TicketContract.sol` (pragma `^0.8.22`) — main contract
Upgradeable: `Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable,
PausableUpgradeable`. Constructor `_disableInitializers()`; state set in
`initialize(baseToken, vault, WETH, router)`.

- **Economics:** `ticketPrice` (default 1e18 HONEY), `teamPercentage` (default 10%,
  cap 20%), `ozFees` (default 25%), `slippageTolerance` (default 50 bps, cap 10%).
  Fees/slippage are basis points (10000 = 100%).
- **`purchaseTicket(address _token, uint256 numOfTicket)`** (payable, `whenNotPaused
  nonReentrant`): if paying in HONEY, splits transfer directly; if paying in BERA
  (`address(0)` sentinel) / other token, refunds ETH excess, swaps input→HONEY, then
  distributes to team / vault / admin. Bumps `userInfo` balance, emits
  `TicketPurchased`.
- **Pricing/quote views** (UniswapV2 `getAmountsOut`/`getAmountsIn`, direct-then-via-WETH
  fallback): `getPrice`, `getTokenToBasePrice`, `getBaseToTokenPrice`,
  `getBaseAmountForToken`, `getBaseToWethPrice`, `getWethToBasePrice`,
  `getBasePriceInToken`, `getTokenPriceInBase`, `getBestPathToBase`,
  `getBestPathFromBase`, `calculateMinAmountOut`, plus explicit-path variants.
- **Admin (`onlyOwner`):** `addToken`/`removeToken`, `setAdmin`, `setVaultAddress`,
  `setRouterAddress`, `setSlippageTolerance`, `setBaseToken`, `setOZFees`,
  `setTeamPercentage`, `setTicketPrice`, `pause`/`unpause`. Has `receive()`.

### `VaultContract.sol` → contract `HoneyVault`
Upgradeable (same OZ mixins). `initialize(address _honeyToken)` sets `honeyToken`
and `admin = msg.sender`.
- `deposit(amount)` — anyone, `whenNotPaused`.
- `withdraw(user, amount)` — **`onlyAdmin`** (distinct from owner!), `whenNotPaused`.
- `vaultBalance()` view; `setHoneyAddress`, `setAdmin` (both `onlyOwner`),
  `setPaused(bool)`.
- **Dual-authority model:** `onlyOwner` for config vs custom `onlyAdmin` for
  withdrawals — owner and admin are different roles.

### `SwapQuoteQuery.sol` (pragma `^0.8.0`) — quote oracle
Upgradeable (`Initializable, OwnableUpgradeable`). `initialize(honey, bera, router)`
stores router + `factory` (from `router.factory()`) + WBERA + HONEY. View-only
mirror of the Ticket pricing helpers, HONEY/WBERA-named
(`getTokenToHoneyPrice`, `getHoneyToTokenPrice`, `getBestPathToHoney`, etc.). No
state-changing logic beyond init.

## Commands

`package.json` has **no scripts** — use the Hardhat CLI directly:

```bash
npx hardhat compile
npx hardhat test          # NOTE: no test files exist yet, despite the README
npx hardhat node          # local chain
```

Deploy via Ignition (per module):

```bash
# full stack: ProxyAdmin + HoneyVault + TicketContract behind transparent proxies
npx hardhat ignition deploy ./ignition/modules/deploy.js --network berachain_bepolia

# individual modules
npx hardhat ignition deploy ./ignition/modules/deployVault.js --network berachain
npx hardhat ignition deploy ./ignition/modules/deployTicket.js --network berachain_bepolia
npx hardhat ignition deploy ./ignition/modules/deploySwapQuote.js --network berachain
```

Requires `PRIVATE_KEY` in `.env`. The `deploy.js` / `deployVault.js` modules use the
**Transparent Upgradeable Proxy + ProxyAdmin** pattern and call the initializers.

## Deployed addresses

**Mainnet (chainId 80094)** — from `data.doc`:
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
  `HoneyVault`; some files/ledgers call things "TokenSwapper".
- **`referance/` is not compiled** (misspelled dir; imports resolve outside the
  tree). It's legacy/example code (old NFT-tier minter, a PriceOracle) — ignore it.
- **`deployTicket.js` and `deploySwapQuote.js` are stale/experimental.** They deploy
  contracts directly with constructor args, passing what are actually `initialize`
  params positionally — but the constructors are parameterless and call
  `_disableInitializers()`, so state is **not** initialized. Real deployments go
  through the proxy modules (`deploy.js` / `deployVault.js`).
- **`deploySwapQuote.js` reads `bepoliaDetails.wbera` / `.kodiakRouter`** which don't
  exist in `bepoliaDetails.json` (only `honey/vault/bera/router`) → `undefined`.
  Broken as written.
- **DEX assumption:** all pricing/swaps assume a UniswapV2-compatible router (Kodiak),
  with WETH/WBERA as the intermediary hop. `address(0)` is the native-BERA/ETH
  sentinel throughout.
- **`decimals = 10**18`** is used as a scaling constant, not an ERC-20 `decimals()`
  read.
- **Dead config:** `package.json` exports `./pathFinder` and depends on `ngraph.*`,
  but there is no `pathFinder/` dir. README is the default Hardhat template. No
  tests exist.
- **Never commit** `.env` or the `PRIVATE_KEY`. `.gitignore` already excludes `.env`,
  `node_modules`, `cache`, `artifacts`, typechain, coverage.
