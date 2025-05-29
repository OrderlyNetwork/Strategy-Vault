const { ethers } = require("hardhat")
const deployment = require('../../../deployment.json');

async function main() {

    const VaultAdapter = await ethers.getContractFactory("VaultAdapter");
    const VaultAdapterContract = await VaultAdapter.deploy();
    await VaultAdapterContract.waitForDeployment();

    const implAddr = VaultAdapterContract.target;
    console.log("- VaultAdapter Implementation Address:", implAddr);

    //upgrade
    //!need to change with your env
    const env = "dev";

    const vaultAdapter = await ethers.getContractAt(
        "VaultAdapter",
        deployment[env].vaultAdapter
    )

    const impl = implAddr;
    tx = await vaultAdapter.upgradeToAndCall(impl, "0x")
    await tx.wait();
    console.log("✅ VaultAdapter upgrade completed successfully!");
}

main().catch(error => {
    console.error("\n❌ Error during upgrade:", error)
    process.exitCode = 1
})
