const { ethers } = require("hardhat")
const deployment = require('../../../deployment.json');
const config = require('../../../config.json');

async function main() {
  //!need to change with your env
  const env = "dev";

  const protocolVault = await ethers.getContractAt(
    "ProtocolVault",
    deployment[env].protocolVault
  )

  // tx = await protocolVault.setLedgerEid(40200);
  // await tx.wait()
  // const ledgerEid = await protocolVault.ledgerEid();
  // console.log("setLedgerEid is:", ledgerEid)

  // tx = await protocolVault.setMinDepositForLP(0);
  // await tx.wait()
  // console.log("setMinDepositForLP done")

  // tx = await protocolVault.setAllowedStrategyProvider("0xc451c10ed20a359c3e2a22c902c525dca1d01179b76ac7b14c3a0dbdfccd949a", true);
  // await tx.wait()
  // console.log("setAllowedStrategyProvider done")

  //set dex vault 
  // tx = await protocolVault.setOrderlyDexVault(deployment[env].dex);
  // await tx.wait()
  // console.log("setOrderlyDexVault:", await protocolVault.dexVault());

  //set crossChainManager
  tx = await protocolVault.setCrossChainManager(deployment[env].crossChainManager);
  await tx.wait()
  console.log("CrossChainManager set successfully")
}

main()
