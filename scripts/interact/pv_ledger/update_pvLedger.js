const { ethers } = require("hardhat")
const hre = require("hardhat")
const deployment = require('../../../deployment/deployment.json');
const { checkNetworkEnvRestrictions } = require("../../../tasks/utils");
const { verifyContract } = require("../../utils/verifyContract");

async function main() {
    //!need to change with your env
    const env = "qa";
    const currentNetwork = hre.network.name;

    checkNetworkEnvRestrictions(currentNetwork, env);

    //limit current network can only be orderly or orderly
    const ProtocolVaultLedger = await ethers.getContractFactory("ProtocolVaultLedger");
    const ProtocolVaultLedgerContract = await ProtocolVaultLedger.deploy();
    await ProtocolVaultLedgerContract.waitForDeployment();

    const implAddr = ProtocolVaultLedgerContract.target;
    console.log("ProtocolVaultLedgerContract Impl deployed to:", implAddr);

    await verifyContract(implAddr, [], "ProtocolVaultLedger Implementation");

    //update
    const protocolVaultLedger = await ethers.getContractAt(
        "ProtocolVaultLedger",
        deployment[env].pvLedger
    )
    const impl = implAddr;
    tx = await protocolVaultLedger.upgradeToAndCall(impl, "0x")
    await tx.wait();
    console.log(`✅ ${env} ledger upgraded successfully`);
}



main().catch(error => {
    console.error(error)
    process.exitCode = 1
})

