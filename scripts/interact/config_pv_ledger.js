const { ethers } = require("hardhat")

async function main() {
    //test: 0x20A69D786Fe0C91fc95aD1361e4626a92065aE39
    let pv_ledger = "0x20A69D786Fe0C91fc95aD1361e4626a92065aE39"
    let operator = "0x4e9FeE6661422BBD72e8133121E9387bf238C2e1"
    const pvLedger = await ethers.getContractAt(
        "ProtocolVaultLedger",
        pv_ledger
    )

    
    tx = await pvLedger.setOperatorManager(operator);
    await tx.wait();
    console.log("setOperatorManager done")
}

main()
