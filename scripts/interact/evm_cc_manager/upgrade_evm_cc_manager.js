const { ethers } = require("hardhat")
const deployment = require('../../../deployment.json');

async function main() {
    const VaultCrossChainManager = await ethers.getContractFactory("VaultCrossChainManager");
    const VaultCrossChainManagerContract = await VaultCrossChainManager.deploy();
    await VaultCrossChainManagerContract.waitForDeployment();

    const implAddr = VaultCrossChainManagerContract.target;
    console.log("VaultCrossChainManagerContract Impl deployed to:", implAddr);

    //upgrade
    //!need to change with your env
    const env = "qa";

    const vaultCrossChainManager = await ethers.getContractAt(
        "VaultCrossChainManager",
        deployment[env].crossChainManager
    )

    const impl = implAddr;
    tx = await vaultCrossChainManager.upgradeToAndCall(impl, "0x")
    await tx.wait();
    console.log("upgrade VaultCrossChainManager contract successfully");
}



main().catch(error => {
    console.error(error)
    process.exitCode = 1
})

