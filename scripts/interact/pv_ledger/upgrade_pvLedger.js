const { ethers } = require("hardhat")
const deployment = require('../../../deployment.json');
const config = require('../../../config.json');

async function main() {
    //!need to change with your env
    const env = "dev";

    const protocolVaultLedger = await ethers.getContractAt(
        "ProtocolVaultLedger",
        deployment[env].pvLedger
    )
    // const impl = await upgrades.forceImport(proxy, ProtocolVault);
    // console.log("Proxy imported from:", impl.target);

    // const instance = await upgrades.upgradeProxy(proxy, ProtocolVault, { kind: "uups" });
    // await instance.waitForDeployment();
    const impl = "0x346423a62dD6D650F1661cC8D034dA2891b61260";
    tx = await protocolVaultLedger.upgradeToAndCall(impl, "0x")
    await tx.wait();
    console.log("upgrade pv ledger successfully");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
