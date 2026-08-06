const { expect } = require("chai");
const { ethers } = require("hardhat");

// Unit tests for the V3 TicketContract accounting. The V3 swap is exercised via
// MockV3Router (ERC-20 exact-output). The native-ETH swap path uses the router's
// multicall/refundETH and is best validated on a testnet/fork — not covered here.
describe("TicketContract (Uniswap V3)", function () {
  const E18 = 10n ** 18n;
  const E6 = 10n ** 6n;              // base (USDG-like) has 6 decimals
  const ONE_TICKET = E18;            // numOfTicket is 1e18-scaled == 1 ticket

  // Defaults from initialize() with a 6-decimal base: ticketPrice 1e6, team 10%, oz 25%.
  const TICKET_AMT = E6;             // 1e6  (1 USDG)
  const TEAM_AMT = E6 / 10n;         // 1e5  (0.1 USDG)
  const OZ_AMT = (25n * E6) / 100n;  // 2.5e5 (0.25 USDG)
  const TOTAL = TICKET_AMT + TEAM_AMT + OZ_AMT; // 1.35e6

  let owner, user, padmin, vault, team, adminS;
  let base, meme, weth, router, ticket;

  async function deadline() {
    const b = await ethers.provider.getBlock("latest");
    return b.timestamp + 3600;
  }

  beforeEach(async () => {
    [owner, user, padmin, vault, team, adminS] = await ethers.getSigners();

    const ERC = await ethers.getContractFactory("MockERC20");
    base = await ERC.deploy("Global Dollar", "USDG", 6); // 6 decimals, like real USDG
    meme = await ERC.deploy("Meme", "MEME", 18);
    weth = await ERC.deploy("Wrapped ETH", "WETH", 18);

    const Router = await ethers.getContractFactory("MockV3Router");
    // mock charges a fixed 2.7 MEME (18-dec) for the exact-output base swap
    router = await Router.deploy(await meme.getAddress(), await base.getAddress(), (27n * E18) / 10n);

    const Impl = await ethers.getContractFactory("TicketContract");
    const impl = await Impl.deploy();
    const initData = Impl.interface.encodeFunctionData("initialize", [
      await base.getAddress(),
      await vault.getAddress(),
      await weth.getAddress(),
      await router.getAddress(),
    ]);
    const Proxy = await ethers.getContractFactory(
      "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy"
    );
    // proxy admin (padmin) must differ from callers so calls route to the implementation
    const proxy = await Proxy.deploy(await impl.getAddress(), padmin.address, initData);
    ticket = Impl.attach(await proxy.getAddress());

    // Route team/oz to distinct addresses so we can assert cleanly.
    await ticket.connect(owner).setTeamAddress(team.address);
    await ticket.connect(owner).setAdmin(adminS.address);
  });

  it("initializes with the expected config", async () => {
    expect(await ticket.baseToken()).to.equal(await base.getAddress());
    expect(await ticket.WETH()).to.equal(await weth.getAddress());
    expect(await ticket.swapRouter()).to.equal(await router.getAddress());
    expect(await ticket.owner()).to.equal(owner.address);
    expect(await ticket.baseUnit()).to.equal(E6);
    expect(await ticket.ticketPrice()).to.equal(E6); // 1 USDG at 6 decimals
  });

  it("buys a ticket paying in the base token (no swap)", async () => {
    await base.mint(user.address, TOTAL);
    await base.connect(user).approve(await ticket.getAddress(), TOTAL);

    await ticket
      .connect(user)
      .purchaseTicket(await base.getAddress(), ONE_TICKET, 0, "0x", await deadline());

    expect(await base.balanceOf(team.address)).to.equal(TEAM_AMT);
    expect(await base.balanceOf(vault.address)).to.equal(TICKET_AMT);
    expect(await base.balanceOf(adminS.address)).to.equal(OZ_AMT);
    expect(await base.balanceOf(await ticket.getAddress())).to.equal(0);
    const info = await ticket.userInfo(user.address);
    expect(info.ticketBalance).to.equal(ONE_TICKET);
  });

  it("getSupportedTokens enumerates the allowlist and stays in sync on add/remove/sync", async () => {
    const memeAddr = await meme.getAddress();
    const wethAddr = await weth.getAddress();
    expect([...(await ticket.getSupportedTokens())]).to.deep.equal([]);

    await ticket.connect(owner).addToken(memeAddr);
    await ticket.connect(owner).addToken(wethAddr);
    expect([...(await ticket.getSupportedTokens())]).to.deep.equal([memeAddr, wethAddr]);

    // swap-remove keeps the survivor
    await ticket.connect(owner).removeToken(memeAddr);
    expect([...(await ticket.getSupportedTokens())]).to.deep.equal([wethAddr]);

    // backfill is idempotent: weth already listed, meme no longer supported → both skipped
    await ticket.connect(owner).syncSupportedTokens([wethAddr, memeAddr]);
    expect([...(await ticket.getSupportedTokens())]).to.deep.equal([wethAddr]);
  });

  it("buys a ticket paying in an allowlisted token (V3 exact-output) and refunds the remainder", async () => {
    await ticket.connect(owner).addToken(await meme.getAddress());

    const maxIn = 3n * E18;                 // cap: 3 MEME
    const expectedSpent = (27n * E18) / 10n; // mock's fixed 2.7 MEME
    const expectedRefund = maxIn - expectedSpent; // 0.3 MEME

    await meme.mint(user.address, maxIn);
    await meme.connect(user).approve(await ticket.getAddress(), maxIn);
    await base.mint(await router.getAddress(), TOTAL); // router must hold the base it pays out

    await ticket
      .connect(user)
      .purchaseTicket(await meme.getAddress(), ONE_TICKET, maxIn, "0x1234", await deadline());

    // base distributed exactly
    expect(await base.balanceOf(team.address)).to.equal(TEAM_AMT);
    expect(await base.balanceOf(vault.address)).to.equal(TICKET_AMT);
    expect(await base.balanceOf(adminS.address)).to.equal(OZ_AMT);
    expect(await base.balanceOf(await ticket.getAddress())).to.equal(0);
    // router received exactly the spent input; user got the remainder back
    expect(await meme.balanceOf(await router.getAddress())).to.equal(expectedSpent);
    expect(await meme.balanceOf(user.address)).to.equal(expectedRefund);
    expect(await meme.balanceOf(await ticket.getAddress())).to.equal(0);
  });

  it("buys a ticket paying in native ETH (V3 exact-output via multicall + refundETH)", async () => {
    const fixedIn = 5n * 10n ** 17n; // mock charges 0.5 ETH
    const maxIn = 1n * E18;          // amountInMaximum = 1 ETH
    await router.setFixedAmountIn(fixedIn);
    await base.mint(await router.getAddress(), TOTAL); // router pays out base

    const before = await ethers.provider.getBalance(user.address);
    const tx = await ticket
      .connect(user)
      .purchaseTicket(
        "0x0000000000000000000000000000000000000000",
        ONE_TICKET,
        maxIn,
        "0x1234",
        await deadline(),
        { value: maxIn }
      );
    const rcpt = await tx.wait();
    const gas = rcpt.gasUsed * rcpt.gasPrice;
    const after = await ethers.provider.getBalance(user.address);

    // base distributed exactly
    expect(await base.balanceOf(team.address)).to.equal(TEAM_AMT);
    expect(await base.balanceOf(vault.address)).to.equal(TICKET_AMT);
    expect(await base.balanceOf(adminS.address)).to.equal(OZ_AMT);
    // the ticket contract keeps no ETH; the router kept exactly the spent amount
    expect(await ethers.provider.getBalance(await ticket.getAddress())).to.equal(0);
    expect(await ethers.provider.getBalance(await router.getAddress())).to.equal(fixedIn);
    // user paid only the spent ETH (+ gas); the surplus was refunded
    expect(before - after - gas).to.equal(fixedIn);
    const info = await ticket.userInfo(user.address);
    expect(info.ticketBalance).to.equal(ONE_TICKET);
  });

  it("reverts buying with a non-allowlisted token", async () => {
    await meme.mint(user.address, 3n * E18);
    await meme.connect(user).approve(await ticket.getAddress(), 3n * E18);
    await expect(
      ticket
        .connect(user)
        .purchaseTicket(await meme.getAddress(), ONE_TICKET, 3n * E18, "0x1234", await deadline())
    ).to.be.revertedWith("Token not supported");
  });

  it("reverts once the deadline has passed", async () => {
    await base.mint(user.address, TOTAL);
    await base.connect(user).approve(await ticket.getAddress(), TOTAL);
    const past = (await ethers.provider.getBlock("latest")).timestamp - 1;
    await expect(
      ticket.connect(user).purchaseTicket(await base.getAddress(), ONE_TICKET, 0, "0x", past)
    ).to.be.revertedWith("Deadline passed");
  });

  it("enforces onlyOwner on addToken and setRouterAddress", async () => {
    await expect(
      ticket.connect(user).addToken(await meme.getAddress())
    ).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(
      ticket.connect(user).setRouterAddress(user.address)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("blocks purchases while paused", async () => {
    await base.mint(user.address, TOTAL);
    await base.connect(user).approve(await ticket.getAddress(), TOTAL);
    await ticket.connect(owner).pause();
    await expect(
      ticket.connect(user).purchaseTicket(await base.getAddress(), ONE_TICKET, 0, "0x", await deadline())
    ).to.be.revertedWith("Pausable: paused");
  });

  // ---- L-2: reject ETH on non-ETH payment paths ----
  it("rejects ETH sent with a base-token purchase", async () => {
    await base.mint(user.address, TOTAL);
    await base.connect(user).approve(await ticket.getAddress(), TOTAL);
    await expect(
      ticket
        .connect(user)
        .purchaseTicket(await base.getAddress(), ONE_TICKET, 0, "0x", await deadline(), { value: 1n })
    ).to.be.revertedWith("No ETH expected");
  });

  it("rejects ETH sent with an ERC-20 purchase", async () => {
    await ticket.connect(owner).addToken(await meme.getAddress());
    await meme.mint(user.address, 3n * E18);
    await meme.connect(user).approve(await ticket.getAddress(), 3n * E18);
    await base.mint(await router.getAddress(), TOTAL);
    await expect(
      ticket
        .connect(user)
        .purchaseTicket(await meme.getAddress(), ONE_TICKET, 3n * E18, "0x1234", await deadline(), { value: 1n })
    ).to.be.revertedWith("No ETH expected");
  });

  // ---- L-3: owner rescue of stranded assets ----
  it("lets the owner rescue stranded ERC-20 and blocks non-owners", async () => {
    const amt = 12345n;
    await base.mint(await ticket.getAddress(), amt);
    await expect(
      ticket.connect(user).rescueERC20(await base.getAddress(), user.address, amt)
    ).to.be.revertedWith("Ownable: caller is not the owner");
    await ticket.connect(owner).rescueERC20(await base.getAddress(), team.address, amt);
    expect(await base.balanceOf(team.address)).to.equal(amt);
    expect(await base.balanceOf(await ticket.getAddress())).to.equal(0);
  });

  it("lets the owner rescue stranded ETH", async () => {
    const amt = 10n ** 15n;
    await owner.sendTransaction({ to: await ticket.getAddress(), value: amt });
    const before = await ethers.provider.getBalance(team.address);
    await ticket.connect(owner).rescueETH(team.address, amt);
    expect((await ethers.provider.getBalance(team.address)) - before).to.equal(amt);
  });

  // ---- L-1: vault zero-address guard in initialize ----
  it("reverts initialize with a zero vault address", async () => {
    const Impl = await ethers.getContractFactory("TicketContract");
    const impl2 = await Impl.deploy();
    const badInit = Impl.interface.encodeFunctionData("initialize", [
      await base.getAddress(),
      "0x0000000000000000000000000000000000000000",
      await weth.getAddress(),
      await router.getAddress(),
    ]);
    const Proxy = await ethers.getContractFactory(
      "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy"
    );
    await expect(Proxy.deploy(await impl2.getAddress(), padmin.address, badInit)).to.be.reverted;
  });

  // ---- M-1: oracle deviation bound with staleness / round-completeness ----
  describe("oracle deviation bound", () => {
    let memeFeed, tNow;
    beforeEach(async () => {
      await ticket.connect(owner).addToken(await meme.getAddress());
      await base.mint(await router.getAddress(), TOTAL);
      await meme.mint(user.address, 3n * E18);
      await meme.connect(user).approve(await ticket.getAddress(), 3n * E18);

      tNow = (await ethers.provider.getBlock("latest")).timestamp;
      const Agg = await ethers.getContractFactory("MockAggregator");
      // meme = $0.50, base = $1.00 (both 8-dec). Oracle-implied input for 1.35 USDG out is
      // 2.7 MEME — exactly the mock router's fixed spend, so deviation == 0.
      memeFeed = await Agg.deploy(8, 5n * 10n ** 7n, tNow);
      const baseFeed = await Agg.deploy(8, 1n * 10n ** 8n, tNow);
      await ticket.connect(owner).setPriceFeed(await meme.getAddress(), await memeFeed.getAddress());
      await ticket.connect(owner).setPriceFeed(await base.getAddress(), await baseFeed.getAddress());
      await ticket.connect(owner).setMaxOracleDeviation(500); // 5%
    });

    it("passes when the swap price matches the oracle and feeds are fresh", async () => {
      await ticket
        .connect(user)
        .purchaseTicket(await meme.getAddress(), ONE_TICKET, 3n * E18, "0x1234", await deadline());
      expect(await base.balanceOf(vault.address)).to.equal(TICKET_AMT);
    });

    it("reverts when a feed is stale", async () => {
      await memeFeed.setUpdatedAt(tNow - 7200); // 2h old > 1h default staleness
      await expect(
        ticket
          .connect(user)
          .purchaseTicket(await meme.getAddress(), ONE_TICKET, 3n * E18, "0x1234", await deadline())
      ).to.be.revertedWith("Oracle price too old");
    });

    it("reverts on an incomplete round", async () => {
      await memeFeed.setIncompleteRound();
      await expect(
        ticket
          .connect(user)
          .purchaseTicket(await meme.getAddress(), ONE_TICKET, 3n * E18, "0x1234", await deadline())
      ).to.be.revertedWith("Stale oracle round");
    });
  });
});
