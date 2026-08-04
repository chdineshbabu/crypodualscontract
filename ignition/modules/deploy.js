const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");
const { getDetails } = require("./_details");
const details = getDetails();

module.exports = buildModule("DeployModule", (m) => {
    // Deploy ProxyAdmin first
    const proxyAdmin = m.contract(
        "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin",
        [],
        { id: "TicketProxyAdmin", from: m.getAccount(0) }
    );

    // Deploy DuelsVault implementation (upgradeable, uses initialize)
    const duelsVaultImplementation = m.contract("DuelsVault", [], {
        id: "DuelsVaultImplementation",
        from: m.getAccount(0)
    });

    // Deploy TicketContract implementation (upgradeable)
    const ticketImplementation = m.contract("TicketContract", [], {
        id: "TicketImplementation",
        from: m.getAccount(0)
    });

    // Deploy DuelsVault proxy, initializing ATOMICALLY in the constructor. Passing the
    // encoded initialize() calldata as the proxy's `_data` means there is never an
    // uninitialized-proxy window for an attacker to front-run initialize() and seize
    // ownership/admin (the deployer remains msg.sender inside the delegatecall).
    const initVault = m.encodeFunctionCall(duelsVaultImplementation, "initialize", [
        details.baseToken,
    ]);
    const duelsVaultProxy = m.contract(
        "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy",
        [duelsVaultImplementation, proxyAdmin, initVault],
        { id: "DuelsVaultProxy", from: m.getAccount(0) }
    );

    // Deploy TicketContract proxy, also initialized atomically. The vault address it is
    // initialized with is the vault PROXY (a future dependency, so it deploys first).
    const initTicket = m.encodeFunctionCall(ticketImplementation, "initialize", [
        details.baseToken,
        duelsVaultProxy,
        details.weth,
        details.router,
    ]);
    const ticketProxy = m.contract(
        "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy",
        [ticketImplementation, proxyAdmin, initTicket],
        { id: "TicketProxy", from: m.getAccount(0) }
    );

    // Typed handles at the proxy addresses for convenience / post-deploy config.
    const duelsVault = m.contractAt("DuelsVault", duelsVaultProxy, { id: "DuelsVaultAtProxy" });
    const ticket = m.contractAt("TicketContract", ticketProxy, { id: "TicketAtProxy" });

    return {
        duelsVault,
        duelsVaultImplementation,
        duelsVaultProxy,
        ticket,
        ticketImplementation,
        proxyAdmin,
        ticketProxy
    };
});
