const { ethers } = require("hardhat")

async function main() {
    let factoryAddr = "0xdf2da6d4c2e893b727bba966054c86bd38d3f150"
    const factory = await ethers.getContractAt(
        "VaultFactory",
        factoryAddr
    )

    console.log(await factory.owner())
}

main()
