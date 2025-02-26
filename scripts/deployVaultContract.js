const hre = require("hardhat");

async function main() {
  const HoneyVault = await hre.ethers.getContractFactory("HoneyVault");
  const honeyVault = await HoneyVault.deploy();
  await honeyVault.deployed();
  console.log("HoneyVault deployed to:", honeyVault.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});