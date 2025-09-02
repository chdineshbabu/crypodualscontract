const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");
const bepoliaDetails = require("./bepoliaDetails.json");

module.exports = buildModule("DeployModule", (m) => {
    // Deploy ProxyAdmin first
    const proxyAdmin = m.contract(
        "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin",
        [],
        { id: "TicketProxyAdmin", from: m.getAccount(0) }
    );

    // Deploy HoneyVault implementation (upgradeable, uses initialize) after ProxyAdmin
    const honeyVaultImplementation = m.contract("HoneyVault", [], {
        id: "HoneyVaultImplementation",
        from: m.getAccount(0)
    });

    // Deploy TicketContract implementation (upgradeable)
    const ticketImplementation = m.contract("TicketContract", [], {
        id: "TicketImplementation",
        from: m.getAccount(0)
    });

    // Ensure Ticket implementation deploys after HoneyVault implementation to serialize txs

    // Deploy TransparentUpgradeableProxy pointing to Ticket implementation; init separately
    const ticketProxy = m.contract(
        "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy",
        [ticketImplementation, proxyAdmin, "0x"],
        { id: "TicketProxy", from: m.getAccount(0) }
    );

    // Deploy TransparentUpgradeableProxy for HoneyVault; initialize via proxy after
    const honeyVaultProxy = m.contract(
        "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy",
        [honeyVaultImplementation, proxyAdmin, "0x"],
        { id: "HoneyVaultProxy", from: m.getAccount(0) }
    );

    // Initialize HoneyVault via its proxy
    const honeyVault = m.contractAt("HoneyVault", honeyVaultProxy, { id: "HoneyVaultAtProxy" });
    m.call(honeyVault, "initialize", [
        bepoliaDetails.honey
    ], { id: "InitializeHoneyVault", from: m.getAccount(0) });

    // Initialize TicketContract via the proxy
    const ticket = m.contractAt("TicketContract", ticketProxy, { id: "TicketAtProxy" });
    m.call(ticket, "initialize", [
        bepoliaDetails.honey,
        honeyVault,
        bepoliaDetails.bera,
        bepoliaDetails.router
    ], { id: "InitializeTicket", from: m.getAccount(0) });

    return {
        honeyVault: honeyVault,
        honeyVaultImplementation,
        honeyVaultProxy,
        ticketImplementation,
        proxyAdmin,
        ticketProxy
    };
}); 