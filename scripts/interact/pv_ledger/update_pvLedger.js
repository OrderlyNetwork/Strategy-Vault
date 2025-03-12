const { ethers } = require("hardhat")
const deployment = require('../../../deployment.json');

async function main() {
    const ProtocolVaultLedger = await ethers.getContractFactory("ProtocolVaultLedger");
    const ProtocolVaultLedgerContract = await ProtocolVaultLedger.deploy();
    await ProtocolVaultLedgerContract.waitForDeployment();

    const implAddr = ProtocolVaultLedgerContract.target;
    console.log("ProtocolVaultLedgerContract Impl deployed to:", implAddr);

    //updage
    //!need to change with your env
    const env = "qa";
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

