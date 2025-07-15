const { ethers } = require("hardhat")
const hre = require("hardhat")
const deployment = require('../../../deployment.json');

async function main() {
    const ProtocolVault = await ethers.getContractFactory("ProtocolVault");
    const ProtocolVaultContract = await ProtocolVault.deploy();
    await ProtocolVaultContract.waitForDeployment();

    const implAddr = ProtocolVaultContract.target;
    console.log("ProtocolVaultContract Impl deployed to:", implAddr);

    // Verify implementation contract
    try {
        console.log(`Verifying ProtocolVault implementation contract: ${implAddr}`);
        await hre.run("verify:verify", {
            address: implAddr,
            constructorArguments: []
        });
        console.log(`✅ ProtocolVault implementation contract verified successfully: ${implAddr}`);
    } catch (error) {
        console.log(`⚠️ ProtocolVault implementation contract verification failed: ${error.message}`);
        // If already verified, no need to throw exception
        if (!error.message.includes("Already Verified") && !error.message.includes("already verified")) {
            console.error("ProtocolVault implementation contract verification error:", error);
        }
    }

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

