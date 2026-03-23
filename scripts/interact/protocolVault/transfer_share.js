const { ethers } = require("hardhat")
const deployment = require('../../../deployment/deployment.json');
const config = require('../../../config.json');


async function main() {
    //!need to change with your env
    const env = "qa";
    const currentNetwork = hre.network.name;
    const [sender] = await ethers.getSigners();
    const orderlyHash = "0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b"

    //prepare config 
    const VaultCrossChainManager = await ethers.getContractAt(
        "VaultCrossChainManager",
        deployment[env].crossChainManager
    )

    //set options
    let tx = await VaultCrossChainManager.setOptions(6, 250000, 0);
    await tx.wait()
    console.log("Option Inner Share Transfer successfully")

    const protocolVault = await ethers.getContractAt(
        "ProtocolVault",
        deployment[env].protocolVault
    )

    //set whitelist for share transfer 
    tx = await protocolVault.updateInnerTransferWhitelist([sender.address], true);
    await tx.wait()
    console.log("Whitelist set successfully")

    // Define transfer parameters
    const toAddress = "0xd5683C2c701F2B95711B6E577d3D11dFc5443fb1"; // Replace with actual receiver address
    const amount = ethers.parseUnits("10", 1); // Amount of shares to transfer (in USDC decimals)



    // Get cross-chain fee
    const nativeFee = await protocolVault.quoteOperation(6, toAddress, amount);
    console.log("Native Fee:", nativeFee.toString())

    // Transfer shares
    tx = await protocolVault.transferShare(toAddress, amount, orderlyHash, {
        value: nativeFee.toString()
    });
    await tx.wait()

    console.log("✅ Transfer share completed with tx:", tx.hash)
}

main().catch(error => {
    console.error(error)
    process.exitCode = 1
})
