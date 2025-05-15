const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("DeployModule", (m) => {
    // Deploy SwapQuoteQuery first as it's used by TicketContract
    const swapQuoteQuery = m.contract("SwapQuoteQuery", [], {
        from: m.getAccount(0)
    });

    // Deploy TokenSwapper
    const tokenSwapper = m.contract("TokenSwapper", [
        "0x4Be03f781C497A489E3cB0287833452cA9B9E80B", // vault address
        "0x6969696969696969696969696969696969696969"  // WETH address
    ], {
        from: m.getAccount(0)
    });

    // Deploy HoneyVault (was VaultContract)
    const honeyVault = m.contract("HoneyVault", [], {
        from: m.getAccount(0)
    });

    // Deploy TicketContract with all its dependencies
    const ticketContract = m.contract("TicketContract", [], {
        from: m.getAccount(0)
    });

    return {
        swapQuoteQuery,
        tokenSwapper,
        honeyVault,
        ticketContract
    };
}); 