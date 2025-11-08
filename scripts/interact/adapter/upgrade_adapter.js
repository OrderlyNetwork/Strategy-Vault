const { ethers } = require("hardhat")
const deployment = require('../../../deployment/deployment.json');
const { verifyContract } = require('../../utils/verifyContract');

async function main() {

    const VaultAdapter = await ethers.getContractFactory("VaultAdapter");
    const VaultAdapterContract = await VaultAdapter.deploy();
    await VaultAdapterContract.waitForDeployment();

    const implAddr = VaultAdapterContract.target;
    console.log("- VaultAdapter Implementation Address:", implAddr);

    // Verify the implementation contract
    console.log("🔍 Verifying VaultAdapter implementation contract...");
    await verifyContract(implAddr, [], "VaultAdapter Implementation");

    //upgrade
    // //!need to change with your env
    // const env = "qa";

    // const vaultAdapter = await ethers.getContractAt(
    //     "VaultAdapter",
    //     deployment[env].vaultAdapter
    // )

    // const impl = implAddr;
    // tx = await vaultAdapter.upgradeToAndCall(impl, "0x")
    // await tx.wait();
    // console.log("✅ VaultAdapter upgrade completed successfully!");
    
}

main().catch(error => {
    console.error("\n❌ Error during upgrade:", error)
    process.exitCode = 1
})
