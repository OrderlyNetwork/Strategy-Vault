const { ethers, upgrades } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log(deployer.address);
    
    const owner = deployer.address;
    PVLedger = await ethers.getContractFactory('ProtocolVaultLedger');
    PVLedgerProxy = await upgrades.deployProxy(PVLedger, [owner], { initializer: 'initialize' });

    console.log(
        `PVLedgerProxy deployed to ${PVLedgerProxy.target}`
    );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
