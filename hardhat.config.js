require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.28",
  networks: {
    berachain: {
      url: "https://rpc.berachain.com/",
      chainId: 80094,
      accounts: [process.env.PRIVATE_KEY],
    },
  },
};
