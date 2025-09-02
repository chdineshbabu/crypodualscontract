const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");
const bepoliaDetails = require("./bepoliaDetails.json");

module.exports = buildModule("VaultDeployModule", (m) => {
    // Deploy a dedicated ProxyAdmin for the vault
    const proxyAdmin = m.contract(
        "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin",
        [],
        { id: "VaultProxyAdmin", from: m.getAccount(0) }
    );

    // Deploy HoneyVault implementation (upgradeable, uses initialize)
    const vaultImplementation = m.contract("HoneyVault", [], {
        id: "HoneyVaultImplementation",
        from: m.getAccount(0),
        // Ensure sequential txs to avoid RPC in-flight limits
        after: [proxyAdmin]
    });

    // Deploy TransparentUpgradeableProxy pointing to the HoneyVault implementation
    const vaultProxy = m.contract(
        "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy",
        [vaultImplementation, proxyAdmin, "0x"],
        { id: "HoneyVaultProxy", from: m.getAccount(0), after: [vaultImplementation] }
    );

    // Interact with the implementation via the proxy and initialize it
    const honeyVault = m.contractAt("HoneyVault", vaultProxy, { id: "HoneyVaultAtProxy" });
    m.call(
        honeyVault,
        "initialize",
        [bepoliaDetails.honey],
        { id: "InitializeHoneyVault", from: m.getAccount(0), after: [vaultProxy] }
    );

    return {
        proxyAdmin,
        vaultImplementation,
        vaultProxy,
        honeyVault
    };
});


