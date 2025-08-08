const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");
const bepoliaDetails = require("./bepoliaDetails.json");

module.exports = buildModule("TicketContractDeployModule", (m) => {
  // Deploy only TicketContract, using already-deployed vault address
  const ticketContract = m.contract(
    "TicketContract",
    [
      bepoliaDetails.honey, // base token
      bepoliaDetails.vault, // existing vault address
      bepoliaDetails.bera, // WBERA (wrapped native)
      bepoliaDetails.router, // UniswapV2-compatible router
    ],
    {
      from: m.getAccount(0),
    }
  );

  return { ticketContract };
});


