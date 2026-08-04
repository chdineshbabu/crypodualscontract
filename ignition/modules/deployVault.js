const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");
const { getDetails } = require("./_details");
const details = getDetails();

module.exports = buildModule("VaultDeployModule", (m) => {
    // Deploy a dedicated ProxyAdmin for the vault
    const proxyAdmin = m.contract(
        "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin",
        [],
        { id: "VaultProxyAdmin", from: m.getAccount(0) }
    );

    // Deploy DuelsVault implementation (upgradeable, uses initialize)
    const vaultImplementation = m.contract("DuelsVault", [], {
        id: "DuelsVaultImplementation",
        from: m.getAccount(0),
        // Ensure sequential txs to avoid RPC in-flight limits
        after: [proxyAdmin]
    });

    // Deploy the proxy, initializing ATOMICALLY via the constructor `_data` so there is no
    // uninitialized-proxy window for an attacker to front-run initialize().
    const initVault = m.encodeFunctionCall(vaultImplementation, "initialize", [
        details.baseToken,
    ]);
    const vaultProxy = m.contract(
        "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy",
        [vaultImplementation, proxyAdmin, initVault],
        { id: "DuelsVaultProxy", from: m.getAccount(0), after: [vaultImplementation] }
    );

    const duelsVault = m.contractAt("DuelsVault", vaultProxy, { id: "DuelsVaultAtProxy" });

    return {
        proxyAdmin,
        vaultImplementation,
        vaultProxy,
        duelsVault
    };
});
