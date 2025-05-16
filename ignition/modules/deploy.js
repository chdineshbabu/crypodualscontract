const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");
const bepoliaDetails = require("./bepoliaDetails.json");

module.exports = buildModule("DeployModule", (m) => {
    // Deploy SwapQuoteQuery first as it's used by TicketContract
    const swapQuoteQuery = m.contract("SwapQuoteQuery", [
        bepoliaDetails.honey, // honey address
        bepoliaDetails.bera, // bera address
        bepoliaDetails.vault // vault address
    ], {
        from: m.getAccount(0)
    });

    // Deploy HoneyVault (was VaultContract)
    const honeyVault = m.contract("HoneyVault", [
        bepoliaDetails.honey // honey token address
    ], {
        from: m.getAccount(0)
    });

    // Deploy TicketContract with all its dependencies
    const ticketContract = m.contract("TicketContract", [
        bepoliaDetails.honey, // base token
        honeyVault, // vault address
        swapQuoteQuery, // swap quote query address
        bepoliaDetails.bera, // WETH address
        bepoliaDetails.beraPoolId, // Bera pool ID
        bepoliaDetails.vault // vault address
    ], {
        from: m.getAccount(0)
    });

    return {
        swapQuoteQuery,
        honeyVault,
        ticketContract
    };
}); 