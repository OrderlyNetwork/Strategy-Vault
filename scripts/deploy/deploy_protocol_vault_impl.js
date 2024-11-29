const { ethers, network } = require("hardhat");



async function main() {
    const ProtocolVault = await ethers.getContractFactory("ProtocolVault");
    const ProtocolVaultContract = await UpgradableCounter.deploy();
    
    const implAddr = ProtocolVaultContract.target;
    console.log("ProtocolVaultContract Impl deployed to:", implAddr);


}



main().catch(error => {
    console.error(error)
    process.exitCode = 1
})

