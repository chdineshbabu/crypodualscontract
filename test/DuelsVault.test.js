const { expect } = require("chai");
const { ethers } = require("hardhat");

// Unit tests for DuelsVault after the audit hardening: SafeERC20, nonReentrant,
// zero-recipient guard, and the setBaseToken "empty first" guard.
describe("DuelsVault", function () {
  const E6 = 10n ** 6n;
  let owner, admin, user, padmin;
  let token, vault;

  beforeEach(async () => {
    [owner, admin, user, padmin] = await ethers.getSigners();

    const ERC = await ethers.getContractFactory("MockERC20");
    token = await ERC.deploy("Global Dollar", "USDG", 6);

    const Impl = await ethers.getContractFactory("DuelsVault");
    const impl = await Impl.deploy();
    const initData = Impl.interface.encodeFunctionData("initialize", [await token.getAddress()]);
    const Proxy = await ethers.getContractFactory(
      "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy"
    );
    // proxy admin (padmin) must differ from callers so calls route to the implementation
    const proxy = await Proxy.deploy(await impl.getAddress(), padmin.address, initData);
    vault = Impl.attach(await proxy.getAddress());

    // Distinct admin (the withdrawal signer) from the owner (config authority).
    await vault.connect(owner).setAdmin(admin.address);
  });

  it("deposits via SafeERC20 and tracks the pooled balance", async () => {
    await token.mint(user.address, 100n * E6);
    await token.connect(user).approve(await vault.getAddress(), 100n * E6);
    await vault.connect(user).deposit(100n * E6);
    expect(await vault.vaultBalance()).to.equal(100n * E6);
  });

  it("only the admin can withdraw", async () => {
    await token.mint(user.address, 100n * E6);
    await token.connect(user).approve(await vault.getAddress(), 100n * E6);
    await vault.connect(user).deposit(100n * E6);

    await expect(vault.connect(user).withdraw(user.address, 1n)).to.be.revertedWith(
      "Only admin can perform this action"
    );
    await vault.connect(admin).withdraw(user.address, 40n * E6);
    expect(await vault.vaultBalance()).to.equal(60n * E6);
    expect(await token.balanceOf(user.address)).to.equal(40n * E6);
  });

  it("rejects withdrawing to the zero address", async () => {
    await expect(vault.connect(admin).withdraw(ethers.ZeroAddress, 0n)).to.be.revertedWith(
      "Invalid recipient"
    );
  });

  it("blocks switching the base token while a balance remains, allows it once emptied", async () => {
    await token.mint(user.address, 10n * E6);
    await token.connect(user).approve(await vault.getAddress(), 10n * E6);
    await vault.connect(user).deposit(10n * E6);

    const ERC = await ethers.getContractFactory("MockERC20");
    const token2 = await ERC.deploy("Other", "OTH", 18);
    await expect(
      vault.connect(owner).setBaseToken(await token2.getAddress())
    ).to.be.revertedWith("Withdraw current token first");

    await vault.connect(admin).withdraw(user.address, 10n * E6);
    await vault.connect(owner).setBaseToken(await token2.getAddress());
    expect(await vault.baseToken()).to.equal(await token2.getAddress());
  });

  it("blocks deposits while paused", async () => {
    await vault.connect(owner).setPaused(true);
    await token.mint(user.address, 1n * E6);
    await token.connect(user).approve(await vault.getAddress(), 1n * E6);
    await expect(vault.connect(user).deposit(1n * E6)).to.be.revertedWith("Pausable: paused");
  });
});
