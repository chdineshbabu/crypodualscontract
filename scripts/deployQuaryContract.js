const hre = require("hardhat");

async function main() {
  const SwapQuoteQuery = await hre.ethers.getContractFactory("SwapQuoteQuery");
  const swapQuoteQuery = await SwapQuoteQuery.deploy();
  await swapQuoteQuery.deployed();
  console.log("SwapQuoteQuery deployed to:", swapQuoteQuery.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});