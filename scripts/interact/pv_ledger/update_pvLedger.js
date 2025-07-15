const { ethers } = require("hardhat")
const hre = require("hardhat")
const deployment = require('../../../deployment.json');
const { checkNetworkEnvRestrictions } = require("../../../tasks/utils");

async function main() {
    //!need to change with your env
    const env = "staging";
    const currentNetwork = hre.network.name;

    checkNetworkEnvRestrictions(currentNetwork, env);

    //limit current network can only be orderly or orderly
    const ProtocolVaultLedger = await ethers.getContractFactory("ProtocolVaultLedger");
    const ProtocolVaultLedgerContract = await ProtocolVaultLedger.deploy();
    await ProtocolVaultLedgerContract.waitForDeployment();

    const implAddr = ProtocolVaultLedgerContract.target;
    console.log("ProtocolVaultLedgerContract Impl deployed to:", implAddr);

    // Verify implementation contract
    try {
        console.log(`Verifying ProtocolVaultLedger implementation contract: ${implAddr}`);
        await hre.run("verify:verify", {
            address: implAddr,
            constructorArguments: []
        });
        console.log(`✅ ProtocolVaultLedger implementation contract verified successfully: ${implAddr}`);
    } catch (error) {
        console.log(`⚠️ ProtocolVaultLedger implementation contract verification failed: ${error.message}`);
        // If already verified, no need to throw exception
        if (!error.message.includes("Already Verified") && !error.message.includes("already verified")) {
            console.error("ProtocolVaultLedger implementation contract verification error:", error);
        }
    }

    //updage
    const protocolVaultLedger = await ethers.getContractAt(
        "ProtocolVaultLedger",
        deployment[env].pvLedger
    )

    const impl = implAddr;
    tx = await protocolVaultLedger.upgradeToAndCall(impl, "0x")
    await tx.wait();
    console.log(` ${env} ledger upgraded successfully`);
}



main().catch(error => {
    console.error(error)
    process.exitCode = 1
})

