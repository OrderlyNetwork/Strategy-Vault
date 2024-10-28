const { ethers } = require("hardhat")

async function main() {
    //address = "0xcf1A28986EF0759B62810247Ac267515F6CD2A30"
    address = "0x4bce55a7a202239ec480fae27f206e7af8c5f20a"

    const protocolVault = await ethers.getContractAt(
        "ProtocolVault",
        address
    )
    

    tx = await protocolVault.initialize(address);
    await tx.wait();
    console.log("ProtocolVault initialized")
}

main()
