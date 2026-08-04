// Post-deploy owner configuration for the V3 TicketContract + DuelsVault.
//
// Run AFTER `ignition deploy ./ignition/modules/deploy.js`, with the deployer key
// (contract owner) in .env. Only the steps whose env vars are set will run, so this is
// safe to re-run. Example:
//
//   TICKET_ADDRESS=0x... VAULT_ADDRESS=0x... \
//   TEAM_ADDRESS=0x... ADMIN_ADDRESS=0x... VAULT_ADMIN=0x... \
//   SUPPORTED_TOKENS=0xtokenA,0xtokenB TICKET_PRICE=1 SLIPPAGE_BPS=100 \
//   npx hardhat run scripts/configure.js --network robinhood
//
// - TICKET_ADDRESS / VAULT_ADDRESS : deployed proxy addresses
// - TEAM_ADDRESS                   : receives the team cut
// - ADMIN_ADDRESS                  : receives the oz fee (ticket admin)
// - VAULT_ADMIN                    : the signer allowed to call DuelsVault.withdraw
//                                    (typically the game-backend signer)
// - SUPPORTED_TOKENS               : comma-separated ERC-20s to allowlist (NOT the base
//                                    token; do NOT include fee-on-transfer tokens)
// - TICKET_PRICE                   : whole base tokens per ticket (e.g. 1 => 1 USDG)
// - SLIPPAGE_BPS                   : advisory slippage in bps (e.g. 100 = 1%)
const hre = require("hardhat");
require("dotenv").config();

function need(name) {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env: ${name}`);
  return v;
}

async function send(label, txPromise) {
  const tx = await txPromise;
  console.log(`  → ${label}: ${tx.hash}`);
  await tx.wait();
}

async function main() {
  const ticketAddr = need("TICKET_ADDRESS");
  const vaultAddr = process.env.VAULT_ADDRESS;

  const [signer] = await hre.ethers.getSigners();
  console.log(`Configuring on ${hre.network.name} as ${signer.address}`);

  const ticket = await hre.ethers.getContractAt("TicketContract", ticketAddr);
  const owner = await ticket.owner();
  if (owner.toLowerCase() !== signer.address.toLowerCase()) {
    throw new Error(`Signer ${signer.address} is not the ticket owner (${owner})`);
  }

  // --- TicketContract config ---
  if (process.env.TEAM_ADDRESS) await send("setTeamAddress", ticket.setTeamAddress(process.env.TEAM_ADDRESS));
  if (process.env.ADMIN_ADDRESS) await send("setAdmin", ticket.setAdmin(process.env.ADMIN_ADDRESS));
  if (vaultAddr) await send("setVaultAddress", ticket.setVaultAddress(vaultAddr));
  if (process.env.TICKET_PRICE) await send(`setTicketPrice(${process.env.TICKET_PRICE})`, ticket.setTicketPrice(process.env.TICKET_PRICE));
  if (process.env.SLIPPAGE_BPS) await send(`setSlippageTolerance(${process.env.SLIPPAGE_BPS})`, ticket.setSlippageTolerance(process.env.SLIPPAGE_BPS));

  const supported = (process.env.SUPPORTED_TOKENS || "").split(",").map((s) => s.trim()).filter(Boolean);
  for (const token of supported) {
    const info = await ticket.supportedTokens(token);
    if (info.tokenAddress && info.tokenAddress !== hre.ethers.ZeroAddress) {
      console.log(`  → addToken ${token}: already allowlisted, skipping`);
    } else {
      await send(`addToken ${token}`, ticket.addToken(token));
    }
  }

  // --- DuelsVault config: allow the game-backend signer to withdraw ---
  if (vaultAddr && process.env.VAULT_ADMIN) {
    const vault = await hre.ethers.getContractAt("DuelsVault", vaultAddr);
    await send("vault.setAdmin", vault.setAdmin(process.env.VAULT_ADMIN));
  }

  console.log("Done.");
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
