require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-ignition");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      { version: "0.8.26" },
      { version: "0.8.20" }
    ]
  },
  networks: {
    bepolis: {
      url: "https://bepolia.rpc.berachain.com/",
      chainId: 80069,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  etherscan: {
    apiKey: {
      bepolis: "not-needed" // Berachain doesn't need an API key for verification
    },
    customChains: [
      {
        network: "bepolis",
        chainId: 80069,
        urls: {
          apiURL: "https://bepolia.rpc.berachain.com/",
          browserURL: "https://bepolia.berachain.com"
        }
      }
    ]
  }
};

