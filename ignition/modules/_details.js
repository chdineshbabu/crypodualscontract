// Selects the Robinhood Chain deploy params for the network Hardhat is currently
// running against, so `--network robinhood` always uses mainnet addresses and
// `--network robinhood_testnet` always uses testnet addresses. Keeping the address
// set bound to the chainId avoids the footgun of deploying mainnet with testnet
// values (or vice-versa).
const all = require("./robinhoodDetails.json");

function getDetails() {
  let chainId;
  try {
    // In an Ignition deploy this resolves to the initialized Hardhat Runtime Env.
    const hre = require("hardhat");
    chainId = hre.network && hre.network.config && hre.network.config.chainId;
  } catch (_) {
    // hardhat not available (e.g. plain require) — fall through to default
  }

  if (chainId === 4663) return all.mainnet;
  if (chainId === 46630) return all.testnet;

  // Default to MAINNET params (mainnet-first). An explicit `--network robinhood_testnet`
  // (chainId 46630) still selects the testnet placeholders above, which revert at
  // initialize on purpose until they are filled in.
  return all.mainnet;
}

module.exports = { getDetails };
