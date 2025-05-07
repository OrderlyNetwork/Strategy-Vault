const { ethers } = require("hardhat")
const deployment = require('../../../deployment.json');
const config = require('../../../config.json');


async function main() {
    //!need to change with your env
    const env = "qa";

    const protocolVault = await ethers.getContractAt(
        "ProtocolVault",
        deployment[env].protocolVault
    )
    const whitelists = [
        
    ]

    tx = await protocolVault.updateLpWhitelist(whitelists,true);
    await tx.wait()
    console.log("updateWhitelist done with tx:", tx.hash)
}

main()


