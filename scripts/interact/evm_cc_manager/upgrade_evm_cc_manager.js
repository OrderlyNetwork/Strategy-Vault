const { ethers } = require("hardhat")
const hre = require("hardhat")
const deployment = require('../../../deployment.json');

async function main() {
    const VaultCrossChainManager = await ethers.getContractFactory("VaultCrossChainManager");
    const VaultCrossChainManagerContract = await VaultCrossChainManager.deploy();
    await VaultCrossChainManagerContract.waitForDeployment();

    const implAddr = VaultCrossChainManagerContract.target;
    console.log("VaultCrossChainManagerContract Impl deployed to:", implAddr);

    // Verify implementation contract
    try {
        console.log(`Verifying VaultCrossChainManager implementation contract: ${implAddr}`);
        await hre.run("verify:verify", {
            address: implAddr,
            constructorArguments: []
        });
        console.log(`✅ VaultCrossChainManager implementation contract verified successfully: ${implAddr}`);
    } catch (error) {
        console.log(`⚠️ VaultCrossChainManager implementation contract verification failed: ${error.message}`);
        // If already verified, no need to throw exception
        if (!error.message.includes("Already Verified") && !error.message.includes("already verified")) {
            console.error("VaultCrossChainManager implementation contract verification error:", error);
        }
    }

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

