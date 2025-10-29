const { ethers } = require("hardhat")
const deployment = require('../../../deployment/deployment.json');
const config = require('../../../config.json');
const { getAccountId, getStrategyProviderId, getVaultId } = require('../../utils/getId');
const { get } = require("http");
const cvDeployment = require('../../../deployment/community.json');


async function main() {
    //!need to change with your env
    const env = "dev";
    const cv = "woo"

    const pvLedger = await ethers.getContractAt(
        "ProtocolVaultLedger",
        deployment[env].pvLedger
    )

    //set AllowedStrategyProvider
    const vault = cvDeployment[cv].address;
    const broker = cvDeployment[cv].broker;
    const vaultId = getVaultId(vault, broker);
    const sp = cvDeployment[cv].sp;
    const spId = getStrategyProviderId(vault, sp, broker);

    console.log("vaultId: ", vaultId);
    console.log("spId: ", spId);
    console.log("sp: ", sp);
    console.log("vault: ", vault);
    console.log("broker: ", broker);
    tx = await pvLedger.setAllowedStrategyProvider(
        vaultId,
        vault,
        sp,
        broker,
        spId,
        true
    )
    await tx.wait();
    console.log("setAllowedStrategyProvider to: ", spId)

}

main()
