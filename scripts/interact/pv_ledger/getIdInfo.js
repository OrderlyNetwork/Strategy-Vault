const { ethers } = require("hardhat")
const deployment = require('../../../deployment/deployment.json');
const cvDeployment = require('../../../deployment/community.json');
const config = require('../../../config.json');
const { getAccountId, getStrategyProviderId, getVaultId } = require('../../utils/getId');
const { get } = require("http");

const broker = "0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b"

async function main() {
    //!need to change with your env
    const env = "qa";
    const cv = "woo"

    const cvVault = cvDeployment[cv].address;
    const pvVault = deployment[env].protocolVault;

    const pvLedger = await ethers.getContractAt(
        "ProtocolVaultLedger",
        deployment[env].pvLedger
    )
    console.log("vault id:", getVaultId(cvVault, cvDeployment[cv].broker)); //0x
    console.log("accountId: ", getAccountId("0x4e9FeE6661422BBD72e8133121E9387bf238C2e1", "0x6ca2f644ef7bd6d75953318c7f2580014941e753b3c6d54da56b3bf75dd14dfc")); //0xf9fdd8648d22ef32e665f03249fe52804bc181cca3a98e3a16d18b41e34bc8d1
    console.log("spId: ", getStrategyProviderId(cvVault, cvDeployment[cv].sp, cvDeployment[cv].broker));//0x652385add0dfdff0e87bee89a7a5e4818145a3e4844c300c7b82baa926d1f0f9
}

main()
