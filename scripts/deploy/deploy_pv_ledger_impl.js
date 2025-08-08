const { ethers, network } = require("hardhat");
const { verifyContract } = require("../utils/verifyContract");

async function main() {
    const ProtocolVaultLedger = await ethers.getContractFactory("ProtocolVaultLedger");
    const ProtocolVaultLedgerContract = await ProtocolVaultLedger.deploy();
    await ProtocolVaultLedgerContract.waitForDeployment();

    const implAddr = ProtocolVaultLedgerContract.target;
    console.log("ProtocolVaultLedgerContract Impl deployed to:", implAddr);

    // verify
    await verifyContract(implAddr, [], "ProtocolVaultLedger Implementation");
}



main().catch(error => {
    console.error(error)
    process.exitCode = 1
})

