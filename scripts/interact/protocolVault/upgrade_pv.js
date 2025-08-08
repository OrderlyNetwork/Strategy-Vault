const { ethers } = require("hardhat")
const hre = require("hardhat")
const deployment = require('../../../deployment.json');
const { verifyContract } = require("../../utils/verifyContract");

async function main() {
    const ProtocolVault = await ethers.getContractFactory("ProtocolVault");
    const ProtocolVaultContract = await ProtocolVault.deploy();
    await ProtocolVaultContract.waitForDeployment();

    const implAddr = ProtocolVaultContract.target;
    console.log("ProtocolVaultContract Impl deployed to:", implAddr);

    // verify
    await verifyContract(implAddr, [], "ProtocolVault Implementation");

    //upgrade
    //!need to change with your env
    const env = "qa";

    const protocolVault = await ethers.getContractAt(
        "ProtocolVault",
        deployment[env].protocolVault
    )

    const impl = implAddr;
    tx = await protocolVault.upgradeToAndCall(impl, "0x")
    await tx.wait();
    console.log("upgrade protocol vault contract successfully");

}



main().catch(error => {
    console.error(error)
    process.exitCode = 1
})

