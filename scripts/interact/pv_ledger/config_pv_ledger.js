const { ethers } = require("hardhat")
const deployment = require('../../../deployment.json');
const config = require('../../../config.json');
const { getAccountId, getStrategyProviderId, getVaultId } = require('../../utils/getId');
const { get } = require("http");

const broker = "0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b"

async function main() {
    //!need to change with your env
    const env = "dev";

    const pvLedger = await ethers.getContractAt(
        "ProtocolVaultLedger",
        deployment[env].pvLedger
    )

    // //set operator 
    // tx = await pvLedger.setOperatorManager(deployment[env].operator);
    // await tx.wait();
    // console.log("setOperatorManager done")

    // //set engine
    // tx = await pvLedger.setEngine(deployment[env].engine);
    // await tx.wait();
    // console.log("set engine done")

    // console.log(await pvLedger.operator());
    // console.log(await pvLedger.engine());

    //set AllowedStrategyProvider
    const vaultId = getVaultId(deployment[env].protocolVault, broker);
    const sp = deployment[env].allowedSP;
    const spId = getStrategyProviderId(deployment[env].protocolVault, sp, broker);
    tx = await pvLedger.setAllowedStrategyProvider(
        vaultId,
        deployment[env].protocolVault,
        sp,
        broker,
        spId,
        true
    )
    await tx.wait();
    console.log("setAllowedStrategyProvider to: ", spId)

    //set crossChainManager
    // tx = await pvLedger.setCrossChainManager(deployment[env].crossChainManager);
    // await tx.wait()
    // console.log("CrossChainManager set successfully")

}

main()
