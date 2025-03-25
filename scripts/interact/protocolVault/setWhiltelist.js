const { ethers } = require("hardhat")
const deployment = require('../../../deployment.json');
const config = require('../../../config.json');


async function main() {
    //!need to change with your env
    const env = "mainnet";

    const protocolVault = await ethers.getContractAt(
        "ProtocolVault",
        deployment[env].protocolVault
    )

    //get current timestamp 
    // const timestamp = Math.floor(Date.now() / 1000);
    // console.log("current timestamp: ", timestamp)

    //set time to 5 mintues later
    // const entTime = timestamp + 300;
    // console.log("entTime: ", entTime)

    //2025-04-10 08:00:00 （UTC + 8）
    let endTime = 1744243200
    tx = await protocolVault.setLpWhitelistConfig(true, endTime);
    await tx.wait()
    console.log("setLpWhitelistConfig done with tx:", tx.hash)

    //add whitelist 
    const whitelists = [
        "0xEd3251D1e96a570971bfCec49b5eF71AF3152F37", //multi-sig
        "0x4A5c7C5633bAF55dDD46B6B9cAF084E839BDa895"  //qa
    ]

    tx = await protocolVault.updateLpWhitelist(whitelists, true);
    await tx.wait()
    console.log("updateWhitelist done with tx:", tx.hash)
}

main()


