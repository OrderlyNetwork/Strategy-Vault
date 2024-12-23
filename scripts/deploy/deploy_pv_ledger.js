const { ethers, upgrades } = require("hardhat");

async function main() {
    const owner = "0x4e9FeE6661422BBD72e8133121E9387bf238C2e1";
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
