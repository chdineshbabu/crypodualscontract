// End-to-end TESTNET deploy using controlled mocks (Robinhood testnet, chainId 46630).
//
// WHY MOCKS: Robinhood testnet has no published canonical USDG and no documented
// Uniswap V3 addresses, so we deploy a token set WE control (MockERC20 + MockV3Router,
// the same mocks that back the 21 unit tests) to validate the full contract pipeline
// on the real testnet: proxy deploy -> configure -> buy (base + ERC-20 swap) -> split
// -> vault deposit/withdraw. Real-DEX swap validation waits for published testnet infra.
//
// Run: npx hardhat run scripts/deployTestnetMocks.js --network robinhood_testnet
//
// Single funded key plays owner + buyer + vault-admin. team/admin (oz-fee) recipients
// are fresh random addresses (receive-only, no gas) so the 3-way split asserts cleanly.

const hre = require("hardhat");
const { ethers } = hre;

const E18 = 10n ** 18n;
const E6 = 10n ** 6n;
const ONE_TICKET = E18;                 // numOfTicket is 1e18-scaled == 1 ticket
const TICKET_AMT = E6;                  // 1 USDG
const TEAM_AMT = E6 / 10n;              // 0.1 USDG (10%)
const OZ_AMT = (25n * E6) / 100n;       // 0.25 USDG (25%)
const TOTAL = TICKET_AMT + TEAM_AMT + OZ_AMT; // 1.35 USDG
const MEME_FIXED_IN = (27n * E18) / 10n;      // mock router charges 2.7 MEME per swap

const fmt6 = (x) => ethers.formatUnits(x, 6);
const line = (s) => console.log(s);

async function deadline() {
  const b = await ethers.provider.getBlock("latest");
  return b.timestamp + 3600;
}

async function main() {
  const [deployer] = await ethers.getSigners();
  const net = await ethers.provider.getNetwork();
  line(`\n=== Robinhood testnet mock deploy ===`);
  line(`network chainId : ${net.chainId}`);
  line(`deployer        : ${deployer.address}`);
  line(`balance         : ${ethers.formatEther(await ethers.provider.getBalance(deployer.address))} ETH\n`);

  // All operator roles (owner/admin/team/oz-fee/vault-admin) resolve to the deployer key,
  // so a single key runs everything (withdraws, allowlist, fee collection). `valutAddress`
  // is the vault PROXY (the prize-pool destination), not an EOA — that is intentional.
  const team = deployer.address;   // team-cut recipient
  const admin = deployer.address;  // oz-fee recipient
  const buyer = deployer.address;  // the only funded (gas) account

  // ---- 1. Mock tokens ----
  const ERC = await ethers.getContractFactory("MockERC20");
  const base = await ERC.deploy("Global Dollar", "USDG", 6); await base.waitForDeployment();
  const meme = await ERC.deploy("Meme", "MEME", 18);        await meme.waitForDeployment();
  const weth = await ERC.deploy("Wrapped ETH", "WETH", 18); await weth.waitForDeployment();
  line(`USDG (base,6d)  : ${await base.getAddress()}`);
  line(`MEME (18d)      : ${await meme.getAddress()}`);
  line(`WETH (18d)      : ${await weth.getAddress()}`);

  // ---- 2. Mock V3 router (meme -> base exact-output), pre-funded with base ----
  const Router = await ethers.getContractFactory("MockV3Router");
  const router = await Router.deploy(await meme.getAddress(), await base.getAddress(), MEME_FIXED_IN);
  await router.waitForDeployment();
  await (await base.mint(await router.getAddress(), 1000n * E6)).wait(); // liquidity to pay swaps
  line(`MockV3Router    : ${await router.getAddress()} (funded 1000 USDG)`);

  // ---- 3. ProxyAdmin ----
  const PA = await ethers.getContractFactory("@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin");
  const proxyAdmin = await PA.deploy(); await proxyAdmin.waitForDeployment();
  line(`ProxyAdmin      : ${await proxyAdmin.getAddress()}`);

  const Proxy = await ethers.getContractFactory(
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy"
  );

  // ---- 4. DuelsVault behind a proxy (initialize atomically) ----
  const Vault = await ethers.getContractFactory("DuelsVault");
  const vaultImpl = await Vault.deploy(); await vaultImpl.waitForDeployment();
  const initVault = Vault.interface.encodeFunctionData("initialize", [await base.getAddress()]);
  const vaultProxy = await Proxy.deploy(await vaultImpl.getAddress(), await proxyAdmin.getAddress(), initVault);
  await vaultProxy.waitForDeployment();
  const vault = Vault.attach(await vaultProxy.getAddress());
  line(`DuelsVault      : ${await vaultProxy.getAddress()} (impl ${await vaultImpl.getAddress()})`);

  // ---- 5. TicketContract behind a proxy (initialize atomically) ----
  const Ticket = await ethers.getContractFactory("TicketContract");
  const ticketImpl = await Ticket.deploy(); await ticketImpl.waitForDeployment();
  const initTicket = Ticket.interface.encodeFunctionData("initialize", [
    await base.getAddress(),
    await vaultProxy.getAddress(),
    await weth.getAddress(),
    await router.getAddress(),
  ]);
  const ticketProxy = await Proxy.deploy(await ticketImpl.getAddress(), await proxyAdmin.getAddress(), initTicket);
  await ticketProxy.waitForDeployment();
  const ticket = Ticket.attach(await ticketProxy.getAddress());
  line(`TicketContract  : ${await ticketProxy.getAddress()} (impl ${await ticketImpl.getAddress()})`);

  // ---- 6. Configure (owner setters + allowlist + vault admin) ----
  line(`\n--- configure ---`);
  await (await ticket.setTeamAddress(team)).wait();
  await (await ticket.setAdmin(admin)).wait();
  await (await ticket.addToken(await meme.getAddress())).wait();
  await (await vault.setAdmin(deployer.address)).wait(); // deployer signs vault.withdraw
  line(`team=${team}\nadmin(oz)=${admin}\nallowlisted MEME + vault admin set`);

  // ============ E2E 1: buy with base token (no swap) ============
  line(`\n--- E2E 1: purchase paying in USDG (no swap) ---`);
  await (await base.mint(buyer, TOTAL)).wait();
  await (await base.approve(await ticket.getAddress(), TOTAL)).wait();
  await (await ticket.purchaseTicket(await base.getAddress(), ONE_TICKET, 0, "0x", await deadline())).wait();

  // NOTE: team/oz-fee recipients == deployer, so those cuts return to the deployer.
  // The split still executes on-chain; the clean, separable checks are vault + residual.
  line(`vault   USDG: ${fmt6(await base.balanceOf(await vaultProxy.getAddress()))}  (expect ${fmt6(TICKET_AMT)})`);
  line(`ticket-contract residual USDG: ${fmt6(await base.balanceOf(await ticket.getAddress()))} (expect 0)`);
  line(`buyer on-chain ticketBalance : ${ethers.formatUnits((await ticket.userInfo(buyer)).ticketBalance, 18)}`);

  // ============ E2E 2: buy with MEME (V3 exact-output swap + refund) ============
  line(`\n--- E2E 2: purchase paying in MEME (swap -> USDG, refund surplus) ---`);
  const maxIn = 3n * E18; // cap 3 MEME; mock spends 2.7, refunds 0.3
  await (await meme.mint(buyer, maxIn)).wait();
  await (await meme.approve(await ticket.getAddress(), maxIn)).wait();
  const memeBefore = await meme.balanceOf(buyer);
  await (await ticket.purchaseTicket(await meme.getAddress(), ONE_TICKET, maxIn, "0x01", await deadline())).wait();
  const memeAfter = await meme.balanceOf(buyer);

  line(`MEME spent   : ${ethers.formatUnits(memeBefore - memeAfter, 18)}  (expect 2.7 — 0.3 refunded)`);
  line(`vault   USDG: ${fmt6(await base.balanceOf(await vaultProxy.getAddress()))}  (expect ${fmt6(2n * TICKET_AMT)} after 2 buys)`);
  line(`buyer ticketBalance: ${ethers.formatUnits((await ticket.userInfo(buyer)).ticketBalance, 18)} (expect 2)`);

  // ============ E2E 3: vault pays a winner (onlyAdmin withdraw) ============
  line(`\n--- E2E 3: vault.withdraw pays a winner ---`);
  const winner = ethers.Wallet.createRandom().address;
  const payout = TICKET_AMT; // pay out 1 USDG of the pooled prize
  const vaultBalBefore = await vault.vaultBalance();
  await (await vault.withdraw(winner, payout)).wait();
  line(`vaultBalance : ${fmt6(vaultBalBefore)} -> ${fmt6(await vault.vaultBalance())}`);
  line(`winner  USDG: ${fmt6(await base.balanceOf(winner))}  (expect ${fmt6(payout)})`);

  // ---- 7. Verify every contract on Blockscout (skips the local hardhat network) ----
  if (Number(net.chainId) !== 31337) {
    line(`\n--- verifying on Blockscout (waiting ~20s for indexing) ---`);
    await new Promise((r) => setTimeout(r, 20000));
    const verify = async (label, address, constructorArguments, contract) => {
      try {
        await hre.run("verify:verify", { address, constructorArguments, ...(contract ? { contract } : {}) });
        line(`  ✓ ${label}`);
      } catch (e) {
        const m = (e.message || "").toLowerCase();
        line(m.includes("already verified") ? `  • already verified: ${label}` : `  ✗ ${label} — ${e.shortMessage || e.message}`);
      }
    };
    const MOCK20 = "contracts/mocks/MockERC20.sol:MockERC20";
    const ROUTER = "contracts/mocks/MockV3Router.sol:MockV3Router";
    const PROXY = "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy";
    const PA = "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin";
    await verify("USDG mock", await base.getAddress(), ["Global Dollar", "USDG", 6], MOCK20);
    await verify("MEME mock", await meme.getAddress(), ["Meme", "MEME", 18], MOCK20);
    await verify("WETH mock", await weth.getAddress(), ["Wrapped ETH", "WETH", 18], MOCK20);
    await verify("MockV3Router", await router.getAddress(), [await meme.getAddress(), await base.getAddress(), MEME_FIXED_IN], ROUTER);
    await verify("ProxyAdmin", await proxyAdmin.getAddress(), [], PA);
    await verify("DuelsVault impl", await vaultImpl.getAddress(), []);
    await verify("TicketContract impl", await ticketImpl.getAddress(), []);
    await verify("DuelsVault proxy", await vaultProxy.getAddress(), [await vaultImpl.getAddress(), await proxyAdmin.getAddress(), initVault], PROXY);
    await verify("TicketContract proxy", await ticketProxy.getAddress(), [await ticketImpl.getAddress(), await proxyAdmin.getAddress(), initTicket], PROXY);
  }

  // ---- summary for backend env ----
  line(`\n=== DONE — set these in the backend .env ===`);
  console.log(JSON.stringify({
    chainId: Number(net.chainId),
    TICKET_ADDRESS: await ticketProxy.getAddress(),
    VAULT_ADDRESS: await vaultProxy.getAddress(),
    baseToken_USDG: await base.getAddress(),
    weth: await weth.getAddress(),
    meme_allowlisted: await meme.getAddress(),
    swapRouter_mock: await router.getAddress(),
    proxyAdmin: await proxyAdmin.getAddress(),
    team, admin,
  }, null, 2));
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
