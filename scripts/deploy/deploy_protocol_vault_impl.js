const { ethers, network } = require("hardhat");
const { verifyContract } = require("../utils/verifyContract");

async function main() {
    const ProtocolVault = await ethers.getContractFactory("ProtocolVault");
    const ProtocolVaultContract = await ProtocolVault.deploy();
    await ProtocolVaultContract.waitForDeployment();

    const implAddr = ProtocolVaultContract.target;
    console.log("ProtocolVaultContract Impl deployed to:", implAddr);

    //verify
    await verifyContract(implAddr, [], "ProtocolVault Implementation");
}



main().catch(error => {
    console.error(error)
    process.exitCode = 1
})

