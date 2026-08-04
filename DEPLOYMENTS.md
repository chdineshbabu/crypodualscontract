# Deployments — Robinhood Chain

Address ledger for the Uniswap **V3** Crypto Duels contracts. Fill the game-contract
addresses after deploying. (Berachain history lives in the old `data.doc`.)

## Robinhood Chain mainnet (chainId 4663)

### Ecosystem (live — from Robinhood Chain / Uniswap docs)
| What | Address |
|------|---------|
| USDG (base token, 6 decimals) | `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` |
| WETH (wrapped native) | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` |
| Uniswap V3 SwapRouter02 | `0xcaf681a66d020601342297493863e78c959e5cb2` |
| Uniswap V3 QuoterV2 | `0x33e885ed0ec9bf04ecfb19341582aadcb4c8a9e7` |
| Uniswap V3 Factory | `0x1f7d7550b1b028f7571e69a784071f0205fd2efa` |

### Game contracts (fill after deploy)
| What | Address |
|------|---------|
| TicketContract (proxy) | `0x… (TODO)` |
| TicketContract ProxyAdmin | `0x… (TODO)` |
| TicketContract implementation | `0x… (TODO)` |
| DuelsVault (proxy) | `0x… (TODO)` |
| DuelsVault ProxyAdmin | `0x… (TODO)` |
| DuelsVault implementation | `0x… (TODO)` |

Ignition also records these under `ignition/deployments/chain-4663/deployed_addresses.json`.

## Robinhood Chain testnet (chainId 46630) — MOCK deploy, 2026-08

> Real ecosystem addresses (canonical USDG / Uniswap V3) are **still not published** on
> testnet. This is a **mock-based** deploy using a token set we control (`MockERC20` +
> `MockV3Router`, the same mocks behind the 21 unit tests) to validate the full pipeline
> on the real testnet. **Swaps use the mock router, NOT real Uniswap liquidity.**
> Redeploy with `npx hardhat run scripts/deployTestnetMocks.js --network robinhood_testnet`.
> Explorer: `https://explorer.testnet.chain.robinhood.com/address/<addr>`

Deployer / owner: `0x5Eb6Cc7E692D00C8f3d824a28A0a515b843795f6`

| What | Address |
|------|---------|
| **TicketContract (proxy)** | `0x09063a0D9dA9E4003cC577550737A0EA534F2966` |
| TicketContract implementation | `0x3d9152950f08090604CFD22A5d0012Fa79967333` |
| **DuelsVault (proxy)** | `0x8cf75404ca5D4d4EC078a8F4234f467Dc206B51A` |
| DuelsVault implementation | `0x1321989766E3eE3C4F373f3047febE02aE59b4a7` |
| ProxyAdmin (shared) | `0x93Ff3f099e018bb705a25070cf5445d3df4Fb18B` |
| USDG (base, 6-dec) — MOCK | `0x10f5c337efee0508568C76811522E74Dc15Fa560` |
| MEME (18-dec, allowlisted) — MOCK | `0xe2529CF29D87C469b4A98E407d6c2D908517dF8e` |
| WETH (18-dec) — MOCK | `0xF1c40bB1b04fF15a66f2084FC94c9a7393d0C6f1` |
| MockV3Router (funded 1000 USDG) | `0xB2F5587f7493d152F4F18F5a8370c85a7508E301` |

Roles: team `0xA7fBA0a24c725aea7aF7B6Ad9e08004b0d55b2aF` (10%), admin/oz-fee
`0x47d6E515b847f35dBc34a13f742Ca1292388B7e4` (25%), **DuelsVault admin (withdraw signer)
`0x3842363f3E8a6683bD54c954fF0BAc4Bfd90884e`** (= the game-backend key's address).

**E2E verified on-chain:** USDG buy → 3-way split + on-chain ticket credit; MEME buy →
exact-output swap (2.7 spent / 0.3 refunded); `vault.withdraw` paid a winner. (Native-ETH
buy path not run on-chain to save gas — covered by local tests.)

## Post-deploy checklist
1. `ignition deploy ./ignition/modules/deploy.js --network robinhood` (ProxyAdmin + DuelsVault + TicketContract + initializers).
2. Record the addresses above (and set `NEXT_PUBLIC_TICKET_ADDRESS` / `VAULT_ADDRESS` for the app).
3. `npx hardhat run scripts/configure.js --network robinhood` with `TEAM_ADDRESS`, `ADMIN_ADDRESS`, `VAULT_ADMIN` (game-backend signer), `SUPPORTED_TOKENS`, `TICKET_PRICE`.
4. Verify on Blockscout: `npx hardhat verify --network robinhood <address> <args...>`.
5. Confirm `DuelsVault.admin` == the game-backend signer (so it can process withdrawals).
6. **Before funds flow:** transfer `ProxyAdmin` ownership + each contract `owner` to a multisig/timelock (audit H-2).
