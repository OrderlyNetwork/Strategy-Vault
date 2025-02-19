const { ethers } = require("hardhat")
const deployment = require('../../../deployment.json');
const config = require('../../../config.json');

async function main() {
    //!need to change with your env
    const env = "qa";

    const VaultCrossChainManager = await ethers.getContractAt(
        "VaultCrossChainManager",
        deployment[env].crossChainManager
    )

    //set options
    // tx = await VaultCrossChainManager.setOptions(0, 120000, 0);
    // await tx.wait()
    // console.log("Option set LP deposit successfully")
    console.log(await VaultCrossChainManager.peers(40200));
}

main()
