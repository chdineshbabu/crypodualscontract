const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");
const { getDetails } = require("./_details");
const details = getDetails();

// Deploys ONLY TicketContract behind a transparent proxy, initialized against an
// already-deployed vault (details.vault). Use this to (re)deploy just the ticket
// contract without touching an existing vault. For a full fresh stack use deploy.js.
//
// NOTE: requires `vault` in robinhoodDetails.json to be a real deployed vault address
// (the mainnet default is a zero placeholder — set it before running this module).
module.exports = buildModule("TicketOnlyDeployModule", (m) => {
  const proxyAdmin = m.contract(
    "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin",
    [],
    { id: "TicketProxyAdmin", from: m.getAccount(0) }
  );

  const ticketImpl = m.contract("TicketContract", [], {
    id: "TicketImplementation",
    from: m.getAccount(0),
    after: [proxyAdmin],
  });

  // Initialize ATOMICALLY via the proxy constructor `_data` (no front-runnable
  // uninitialized-proxy window).
  const initTicket = m.encodeFunctionCall(ticketImpl, "initialize", [
    details.baseToken,
    details.vault,
    details.weth,
    details.router,
  ]);
  const ticketProxy = m.contract(
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy",
    [ticketImpl, proxyAdmin, initTicket],
    { id: "TicketProxy", from: m.getAccount(0), after: [ticketImpl] }
  );

  const ticket = m.contractAt("TicketContract", ticketProxy, { id: "TicketAtProxy" });

  return { proxyAdmin, ticketImpl, ticketProxy, ticket };
});
