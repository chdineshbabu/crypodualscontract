require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-ignition");
require("dotenv").config();

// Deployer key + optional custom RPCs come from .env (never commit real values).
// Public RPCs are rate-limited fallbacks — set RH_*_RPC_URL to your Dwellir/Alchemy
// endpoint for anything beyond a quick test.
const {
  PRIVATE_KEY,
  RH_MAINNET_RPC_URL,
  RH_TESTNET_RPC_URL,
} = process.env;

const accounts = PRIVATE_KEY ? [PRIVATE_KEY] : [];

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.26",
        settings: {
          optimizer: { enabled: true, runs: 50 },
          viaIR: true,
        },
      },
      {
        version: "0.8.22",
        settings: {
          optimizer: { enabled: true, runs: 50 },
          viaIR: true,
        },
      },
    ],
  },
  networks: {
    // Robinhood Chain mainnet — Arbitrum L2, native gas token is ETH.
    robinhood: {
      url: RH_MAINNET_RPC_URL || "https://rpc.mainnet.chain.robinhood.com",
      chainId: 4663,
      accounts,
      saveDeployments: true,
    },
    // Robinhood Chain testnet.
    robinhood_testnet: {
      url: RH_TESTNET_RPC_URL || "https://rpc.testnet.chain.robinhood.com",
      chainId: 46630,
      accounts,
      saveDeployments: true,
    },
  },
  // Contract verification via Blockscout (Robinhood Chain uses Blockscout, not
  // Etherscan). The apiKey value is ignored by Blockscout but must be non-empty.
  etherscan: {
    apiKey: {
      robinhood: "blockscout",
      robinhood_testnet: "blockscout",
    },
    customChains: [
      {
        network: "robinhood",
        chainId: 4663,
        urls: {
          apiURL: "https://robinhoodchain.blockscout.com/api",
          browserURL: "https://robinhoodchain.blockscout.com",
        },
      },
      {
        network: "robinhood_testnet",
        chainId: 46630,
        urls: {
          apiURL: "https://explorer.testnet.chain.robinhood.com/api",
          browserURL: "https://explorer.testnet.chain.robinhood.com",
        },
      },
    ],
  },
  // Blockscout handles verification; Sourcify off to avoid a second prompt.
  sourcify: {
    enabled: false,
  },
};
