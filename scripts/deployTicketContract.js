const hre = require("hardhat");

async function main() {
  const TicketContract = await hre.ethers.getContractFactory("TicketContract");
  const ticketContract = await TicketContract.deploy();
  await ticketContract.deployed();
  console.log("TicketContract deployed to:", ticketContract.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});