// Upgrade the TicketContract implementation behind the existing proxy (same proxy
// address, same vault, same owner/admin, all state preserved). Adds getSupportedTokens().
//
// Run: npx hardhat run scripts/upgradeTicket.js --network robinhood
const hre = require("hardhat");
const { ethers } = hre;

async function main() {
  const [signer] = await ethers.getSigners();
  const PROXY = process.env.TICKET_PROXY || "0x6a4045dAbd637239d1185f73bdC1c77ED6E282B6";
  const PROXY_ADMIN = process.env.PROXY_ADMIN || "0xF1c40bB1b04fF15a66f2084FC94c9a7393d0C6f1";
  // Tokens allowlisted BEFORE this upgrade — backfill them into the new enumerable list.
  const syncTokens = (process.env.SYNC_TOKENS || "0x0c1eD62D7811e5b437e537Ac9d0592469C119C74")
    .split(",").map((s) => s.trim()).filter(Boolean);

  console.log(`network: ${hre.network.name} | signer: ${signer.address}`);
  console.log(`proxy: ${PROXY} | proxyAdmin: ${PROXY_ADMIN}\n`);

  // snapshot pre-upgrade state (must be identical after)
  const before = await ethers.getContractAt("TicketContract", PROXY);
  const snap = {
    owner: await before.owner(), admin: await before.admin(), team: await before.teamAddress(),
    vault: await before.valutAddress(), ticketPrice: (await before.ticketPrice()).toString(),
    dihSupported: await before.supportedTokens("0x0c1eD62D7811e5b437e537Ac9d0592469C119C74"),
  };
  console.log("state BEFORE:", snap);

  // 1) deploy new implementation (no constructor args; _disableInitializers in ctor)
  const Impl = await ethers.getContractFactory("TicketContract");
  const impl = await Impl.deploy();
  await impl.waitForDeployment();
  const implAddr = await impl.getAddress();
  console.log("\nnew implementation:", implAddr);

  // 2) point the proxy at it via ProxyAdmin.upgrade (onlyOwner)
  const pa = await ethers.getContractAt(
    "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin", PROXY_ADMIN);
  const paOwner = await pa.owner();
  if (paOwner.toLowerCase() !== signer.address.toLowerCase()) {
    throw new Error(`Signer is not the ProxyAdmin owner (${paOwner}) — cannot upgrade.`);
  }
  const up = await pa.upgrade(PROXY, implAddr);
  await up.wait();
  console.log("upgrade tx:", up.hash);

  // 3) backfill the enumerable list with pre-upgrade tokens
  const ticket = await ethers.getContractAt("TicketContract", PROXY);
  if (syncTokens.length) {
    const s = await ticket.syncSupportedTokens(syncTokens);
    await s.wait();
    console.log("syncSupportedTokens tx:", s.hash, syncTokens);
  }

  // 4) verify: new getter works + state unchanged
  const list = await ticket.getSupportedTokens();
  const after = {
    owner: await ticket.owner(), admin: await ticket.admin(), team: await ticket.teamAddress(),
    vault: await ticket.valutAddress(), ticketPrice: (await ticket.ticketPrice()).toString(),
  };
  console.log("\ngetSupportedTokens() ->", list);
  console.log("state AFTER :", after);
  const same = snap.owner === after.owner && snap.admin === after.admin && snap.team === after.team &&
    snap.vault === after.vault && snap.ticketPrice === after.ticketPrice;
  console.log(same ? "✅ state preserved (owner/admin/team/vault/price unchanged)" : "❌ STATE CHANGED — investigate");
  console.log(JSON.stringify({ newImplementation: implAddr, upgradeTx: up.hash }, null, 2));
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
