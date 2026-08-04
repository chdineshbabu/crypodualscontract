# Crypto Duels — Smart Contracts

On-chain half of the Crypto Duels game (ticket purchase + pooled custody), deployed on
**Robinhood Chain** (Arbitrum-style L2). See [`CLAUDE.md`](CLAUDE.md) for full developer
context and [`AUDIT_REPORT.md`](AUDIT_REPORT.md) for the security review.

## Contracts

- **`TicketContract.sol`** — buy game tickets priced in a base stablecoin (USDG). Pay in
  the base token directly, or in native ETH / an allowlisted ERC-20 that is swapped to the
  base token via Uniswap **V3 `SwapRouter02.exactOutput`** (exact-output: the protocol
  always receives exactly the ticket total; unspent input is refunded). Proceeds split
  between team, vault, and an admin/oz-fee address. Upgradeable (transparent proxy).
- **`VaultContract.sol`** (`DuelsVault`) — pooled custody of the base token. `deposit` is
  open; `withdraw` is restricted to a dedicated `admin` (the game-backend signer),
  separate from the `owner` config role. Upgradeable.

## Commands

```bash
npx hardhat compile
npx hardhat test        # test/TicketContract.test.js + test/DuelsVault.test.js
npx hardhat node        # local chain
```

Deploy (Hardhat Ignition — proxies are initialized atomically in the proxy constructor).
Mainnet (`robinhood`, chainId 4663) is the default target; `_details.js` supplies mainnet
ecosystem addresses:

```bash
# full stack: ProxyAdmin + DuelsVault + TicketContract behind transparent proxies
npx hardhat ignition deploy ./ignition/modules/deploy.js --network robinhood

# individual modules
npx hardhat ignition deploy ./ignition/modules/deployVault.js  --network robinhood
npx hardhat ignition deploy ./ignition/modules/deployTicket.js --network robinhood

# post-deploy owner config (team/admin/allowlist/vault-admin)
TICKET_ADDRESS=0x.. VAULT_ADDRESS=0x.. TEAM_ADDRESS=0x.. ADMIN_ADDRESS=0x.. VAULT_ADMIN=0x.. \
  npx hardhat run scripts/configure.js --network robinhood

# verify on Blockscout
npx hardhat verify --network robinhood <address> <constructor-args...>
```

Requires `PRIVATE_KEY` (and optionally `RH_MAINNET_RPC_URL` / `RH_TESTNET_RPC_URL`) in a
local `.env` — **never commit it**. `_details.js` auto-selects mainnet vs testnet
ecosystem addresses from the `--network` chainId.

> **Post-deploy, before funds flow:** transfer `ProxyAdmin` ownership, each contract's
> `owner`, and the vault `admin` to a multisig (ideally behind a timelock). These keys can
> upgrade logic and move custodied funds — see `AUDIT_REPORT.md` (H-1, H-2).
