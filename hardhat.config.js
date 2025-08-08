require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-ignition");
require("dotenv").config();

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
    ]
  },
  networks: {
    berachain_bepolia: {
      url: "https://bepolia.rpc.berachain.com/",
      chainId: 80069,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      saveDeployments: true,
    },
    berachain: {
      url: "https://rpc.berachain.com",
      chainId: 80094,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  etherscan: {
    apiKey: {
      berachain_bepolia: "berachain_bepolia",
      berachain: "not-needed" // Berachain mainnet doesn't need an API key for verification
    },
    customChains: [
      {
        network: "berachain_bepolia",
        chainId: 80069,
        urls: {
          apiURL:
            "https://api.routescan.io/v2/network/testnet/evm/80069/etherscan",
          browserURL: "https://bepolia.beratrail.io",
        },
      },
      {
        network: "berachain",
        chainId: 80094,
        urls: {
          apiURL: "https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan",
          browserURL: "https://berachain.com"
        }
      }
    ]
  }
};

