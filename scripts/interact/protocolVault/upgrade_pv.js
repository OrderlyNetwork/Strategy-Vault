const { ethers } = require("hardhat")
const deployment = require('../../../deployment.json');
const config = require('../../../config.json');

async function main() {
    //!need to change with your env
    const env = "dev";

    const proxy = deployment[env].protocolVault;
    const ProtocolVault = await ethers.getContractFactory("ProtocolVault");
    // const impl = await upgrades.forceImport(proxy, ProtocolVault);
    // console.log("Proxy imported from:", impl.target);
    const instance = await upgrades.upgradeProxy(proxy, ProtocolVault, { kind: "uups" });
    await instance.waitForDeployment();

    console.log("upgrade successfully");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
