const { ethers, network } = require("hardhat");
const fs = require("fs");
const { deployKeylessly } = require(`./deploy_keyless`)

const factoryArtifact = JSON.parse(fs.readFileSync(__dirname + `/../utils/factory.json`, "utf8"))
const isDeployEnabled = true // toggle in case you do deployment and verification separately.

async function main() {
    const [wallet] = await ethers.getSigners()

    const balanceOfWallet = await ethers.provider.getBalance(wallet.address)
    console.log(`Using network: ${network.name} (${network.config.chainId}), account: ${wallet.address} having ${ethers.formatUnits(balanceOfWallet, `ether`)} of native currency, RPC url: ${network.config.url}`)
    //console.log(factoryToDeploy)
    const gasLimit = 500000n

    const address = await deployKeylessly(factoryArtifact.contractName, factoryArtifact.bytecode, gasLimit, wallet, isDeployEnabled)
    console.log("Factory address is:", address);

}



main().catch(error => {
    console.error(error)
    process.exitCode = 1
})
