const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");
const bepoliaDetails = require("./bepoliaDetails.json");

module.exports = buildModule("DeployModule", (m) => {
    // Deploy HoneyVault (was VaultContract)
    const honeyVault = m.contract("HoneyVault", [
        bepoliaDetails.honey // honey token address
    ], {
        from: m.getAccount(0)
    });

    // Deploy TicketContract with all its dependencies
    const ticketContract = m.contract("TicketContract", [
        bepoliaDetails.honey, // base token
        honeyVault, // vault address (destination of funds)
        bepoliaDetails.bera, // WETH address
        bepoliaDetails.router // UniswapV2 router address
    ], {
        from: m.getAccount(0)
    });

    return {
        honeyVault,
        ticketContract
    };
}); 