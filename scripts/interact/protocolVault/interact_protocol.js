const { ethers } = require("hardhat")
const deployment = require('../../../deployment.json');
const config = require('../../../config.json');

async function main() {
    //!need to change with your env
    const env = "dev";

    const protocolVault = await ethers.getContractAt(
        "ProtocolVault",
        deployment[env].protocolVault
      )

    //set ledger eid
    tx = await protocolVault.setLedgerEid(40200);
    await tx.wait()
    console.log("setLedgerEid done")

    tx = await protocolVault.setMinDepositForLP(0);
    await tx.wait()
    console.log("setMinDepositForLP done")
}

main()
