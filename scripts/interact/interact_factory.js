const { ethers } = require("hardhat")

async function main() {
    let factoryAddr = "0x2b1E9a839a873E05eeE8D90c6AfF7aA3E724E6cF"
    const factory = await ethers.getContractAt(
        "VaultFactory",
        factoryAddr
    )

    //console.log(await factory.owner())
    await factory.setManagers(
        ["0xDd3287043493E0a08d2B348397554096728B459c"],
        true
    )
    console.log("set managers")
}

main()
