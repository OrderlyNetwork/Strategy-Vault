const { ethers } = require("hardhat")
const deployment = require('../../../deployment/deployment.json');
const config = require('../../../config.json');


async function main() {
    //!need to change with your env
    const env = "dev";

    //prepare config 
    const VaultCrossChainManager = await ethers.getContractAt(
        "VaultCrossChainManager",
        deployment[env].crossChainManager
    )

    // //set options
    // let tx = await VaultCrossChainManager.setOptions(6, 250000, 0);
    // await tx.wait()
    // console.log("Option Inner Share Transfer successfully")

    const protocolVault = await ethers.getContractAt(
        "ProtocolVault",
        deployment[env].protocolVault
    )

    //set whitelist for share transfer
    const whitelist = ["0x58AC0B98C9eC516DC4E75b09aDbF43e1B292E791"]
    tx = await protocolVault.updateInnerTransferWhitelist(whitelist, true);
    await tx.wait()
    console.log("Whitelist set successfully")

}

main().catch(error => {
    console.error(error)
    process.exitCode = 1
})
