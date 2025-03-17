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

    //get current timestamp 
    const timestamp = Math.floor(Date.now() / 1000);
    console.log("current timestamp: ", timestamp)

    //set time to 5 mintues later
    const entTime = timestamp + 300;
    console.log("entTime: ", entTime)

    tx = await protocolVault.setLpWhitelistConfig(true, entTime);
    await tx.wait()
    console.log("setLpWhitelistConfig done with tx:", tx.hash)
}

main()


