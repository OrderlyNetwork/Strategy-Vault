const { ethers } = require("hardhat")
const deployment = require('../../../deployment.json');
const config = require('../../../config.json');
const { getAccountId, getStrategyProviderId, getVaultId } = require('../../utils/getId');
const broker = "0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b"

async function main() {
  //!need to change with your env
  const env = "dev";

  const protocolVault = await ethers.getContractAt(
    "ProtocolVault",
    deployment[env].protocolVault
  )

  tx = await protocolVault.setLedgerEid(40200);
  await tx.wait()
  const ledgerEid = await protocolVault.ledgerEid();
  console.log("setLedgerEid is:", ledgerEid)

  tx = await protocolVault.setMinDepositForLP(0);
  await tx.wait()
  console.log("setMinDepositForLP done")

  //set allowed sp 
  const spId = getStrategyProviderId(deployment[env].protocolVault, deployment[env].allowedSP, broker);
  console.log("spId:", spId)
  tx = await protocolVault.setAllowedStrategyProvider(spId, true);
  await tx.wait()
  console.log("Allowed SP set successfully")

  //set dex vault 
  tx = await protocolVault.setOrderlyDexVault(deployment[env].dex);
  await tx.wait()
  console.log("setOrderlyDexVault:", await protocolVault.dexVault());

  //set crossChainManager
  tx = await protocolVault.setCrossChainManager(deployment[env].crossChainManager);
  await tx.wait()
  console.log("CrossChainManager set successfully")
}

main()
