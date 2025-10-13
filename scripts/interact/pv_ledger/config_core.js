const { ethers, network } = require("hardhat");
const { checkNetworkEnvRestrictions } = require("../../../tasks/utils");
const deployment = require('../../../deployment/deployment.json');
const { verifyContractWithRetry } = require("../../utils/verifyContract");

async function main() {
    //deploy core
    
    const LedgerCoreImpl = await ethers.getContractFactory("LedgerCoreImpl");
    const LedgerCoreImplContract = await LedgerCoreImpl.deploy();
    await LedgerCoreImplContract.waitForDeployment();

    const coreImpl = LedgerCoreImplContract.target;
    console.log("LedgerCoreImplContract Impl deployed to:", coreImpl);

    //config
    //!need to change with your env
    const env = "qa";
    const currentNetwork = hre.network.name;

    checkNetworkEnvRestrictions(currentNetwork, env);

    const protocolVaultLedger = await ethers.getContractAt(
        "ProtocolVaultLedger",
        deployment[env].pvLedger
    );

    tx = await protocolVaultLedger.setCore(coreImpl);
    await tx.wait();
    console.log("Core set to:", coreImpl);

    // Verify contracts on blockchain explorer
    console.log("\n🔍 Starting contract verification...");
    
    // Verify LedgerCoreImpl contract
    await verifyContractWithRetry(
        coreImpl,
        [], // No constructor arguments
        "LedgerCoreImpl"
    );

}



main().catch(error => {
    console.error(error)
    process.exitCode = 1
})
