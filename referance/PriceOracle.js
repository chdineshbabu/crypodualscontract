const fs = require("fs");
const path = require("path");
const { ethers, upgrades } = require("hardhat");

const factory = "0x5e705e184d233ff2a7cb1553793464a9d0c3028f";
const lick = "0xfd704677b2DA0949335f57E3CeC96C4D5E650f12";
const honey = "0x4D539677d52dac89e59365E9F78AB55f935E80C6";
const owner = "0xf85aE605B419386Cd223B71eFc26C15807EB484D"

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (ethers.utils.formatEther(await deployer.getBalance())).toString(), "Bera");

    const NAME = "PriceOracle";
    const Contract = await ethers.getContractFactory(NAME);
    console.log(`Deploying ${NAME}...`);

    const contract = await upgrades.deployProxy(
        Contract, [factory, lick, honey, owner],
        { initializer: "initialize", kind: "transparent" });
    await contract.deployed();

    const deployedAddress = await contract.address;
    console.log("Account balance:", (ethers.utils.formatEther(await deployer.getBalance())).toString(), "Bera");
    console.log(`${NAME} deployed to:`, deployedAddress);

    // **Save address to JSON file**
}



main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

// Run using:
// npx hardhat run --network berachainTestnet scripts/testnet/PairOracle.js

//current deployement: 0x526A784e383cc09AadDE02cB1195F79AfD9520BC

// npx hardhat verify --network berachainTestnet 0x526A784e383cc09AadDE02cB1195F79AfD9520BC