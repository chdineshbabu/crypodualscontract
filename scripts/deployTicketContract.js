const hre = require("hardhat");

async function main() {
  // Deploy the TicketContract
  const TicketContract = await hre.ethers.getContractFactory("TicketContract");

  // Constructor arguments
  const teamAddress = "0xYourTeamAddressHere"; // Replace with the actual team address
  const admin = "0xYourAdminAddressHere"; // Replace with the actual admin address
  const baseToken = "0xYourBaseTokenAddressHere"; // Replace with the actual base token address
  const vaultAddress = "0xYourVaultAddressHere"; // Replace with the actual vault address
  const swapQuoteQuery = "0xYourSwapQuoteQueryAddressHere"; // Replace with the actual SwapQuoteQuery address
  const WETH = "0xYourWETHAddressHere"; // Replace with the actual WETH address
  const BeraPoolId = "0xYourBeraPoolIdHere"; // Replace with the actual BeraPoolId

  const ticketContract = await TicketContract.deploy(
    teamAddress,
    admin,
    baseToken,
    vaultAddress,
    swapQuoteQuery,
    WETH,
    BeraPoolId
  );

  await ticketContract.deployed();

  console.log("TicketContract deployed to:", ticketContract.address);
}

// Run the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });