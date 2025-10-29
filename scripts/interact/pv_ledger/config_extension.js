const { ethers, network } = require("hardhat");
const { checkNetworkEnvRestrictions } = require("../../../tasks/utils");
const deployment = require('../../../deployment/deployment.json');
const { verifyContractWithRetry } = require("../../utils/verifyContract");

async function main() {

    //deploy extension
    const LedgerExtension = await ethers.getContractFactory("LedgerExtension");
    const LedgerExtensionContract = await LedgerExtension.deploy();
    await LedgerExtensionContract.waitForDeployment();

    const extension = LedgerExtensionContract.target;
    console.log("LedgerExtensionContract Impl deployed to:", extension);

    // Verify LedgerExtension contract
    await verifyContractWithRetry(
        extension,
        [], // No constructor arguments
        "LedgerExtension"
    );

    console.log("✅ Contract verification completed!");
    //config
    //!need to change with your env
    const env = "qa";
    const currentNetwork = hre.network.name;

    checkNetworkEnvRestrictions(currentNetwork, env);

    const protocolVaultLedger = await ethers.getContractAt(
        "ProtocolVaultLedger",
        deployment[env].pvLedger
    )

    tx = await protocolVaultLedger.setExtension(extension);
    await tx.wait();
    console.log("Extension set to:", extension);
}



main().catch(error => {
    console.error(error)
    process.exitCode = 1
})

