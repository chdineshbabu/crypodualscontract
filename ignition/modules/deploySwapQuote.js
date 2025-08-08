const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");
const bepoliaDetails = require("./bepoliaDetails.json");

module.exports = buildModule("SwapQuoteDeployModule", (m) => {
    // Deploy SwapQuoteQuery with Kodiak DEX integration
    const swapQuoteQuery = m.contract("SwapQuoteQuery", [
        bepoliaDetails.honey,    // HONEY token address
        bepoliaDetails.wbera,    // WBERA address
        bepoliaDetails.kodiakRouter // Kodiak Router address
    ], {
        from: m.getAccount(0)
    });

    return {
        swapQuoteQuery
    };
});
