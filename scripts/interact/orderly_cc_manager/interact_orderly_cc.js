const { ethers } = require("hardhat")
const deployment = require('../../../deployment.json');
const config = require('../../../config.json');

async function main() {
  //!need to change with your env
  const env = "dev";

  const VaultCrossChainManager = await ethers.getContractAt(
    "VaultCrossChainManager",
    deployment[env].crossChainManager
  )
  //set ledger 
  tx = await VaultCrossChainManager.setLedger(deployment[env].pvLedger);
  await tx.wait()
  console.log("Ledger set successfully")

  //set options
  // tx = await VaultCrossChainManager.setOptions(0, 120000, 0);
  // await tx.wait()
  // console.log("Option set LP deposit successfully")

}

main()
