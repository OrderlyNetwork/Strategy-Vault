const { ethers } = require("hardhat");

async function main() {

    const [deployer] = await ethers.getSigners();
    console.log("deployer address:", deployer.address);

    const Ed25519Factory = await ethers.getContractFactory("Ed25519");
    const ed25519 = await Ed25519Factory.deploy();

    await ed25519.waitForDeployment();

    console.log("✅ Deploy address:", await ed25519.getAddress());
}

main()