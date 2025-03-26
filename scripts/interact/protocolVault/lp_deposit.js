const { ethers } = require("hardhat")
const deployment = require('../../../deployment.json');
const config = require('../../../config.json');


async function main() {
  //!need to change with your env
  const env = "mainnet";
  const currentNetwork = hre.network.name;
  const [sender] = await ethers.getSigners();
  const orderlyHash = "0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b"
  const value = ethers.parseUnits("0.01", 6);
  const protocolVault = await ethers.getContractAt(
    "ProtocolVault",
    deployment[env].protocolVault
  )
  // Define the parameters
  const type = 0; //0 for LP Deposit; 2 for SP_DEPOSIT
  const depositParams = {
    payloadType: type,
    receiver: sender.address,
    token: config[currentNetwork].USDC,
    amount: value,
    brokerHash: orderlyHash
  };

  console.log("Deposit Params: ", depositParams)

  //approve
  // const token = await ethers.getContractAt("IERC20", config[currentNetwork].USDC);
  // const protocolVaultAddress = deployment[env].protocolVault;
  // const allowance = await token.allowance(sender.address, protocolVaultAddress);
  // if (allowance == 0) {
  //   tx = await token.approve(protocolVaultAddress, ethers.MaxUint256);
  //   await tx.wait()
  //   console.log("Approve done")
  // }

  //get lz fee
  const nativeFee = await protocolVault.quoteOperation(type,depositParams.receiver,depositParams.amount);
  console.log("Native Fee: ", nativeFee.toString())
  //deposit
  //const nativeFee = 1190048;
  
  // tx = await protocolVault.deposit(depositParams, { value: nativeFee.toString() }); // Replace with actual value if needed
  // await tx.wait()
  // console.log("Deposit done with tx:", tx.hash)
}

main()


