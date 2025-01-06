const { ethers } = require("hardhat")
const deployment = require('../../../deployment.json');
const config = require('../../../config.json');


async function main() {
  //!need to change with your env
  const env = "dev";
  const currentNetwork = hre.network.name;
  const [sender] = await ethers.getSigners();
  const orderlyHash = "0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b"
  const value = ethers.parseUnits("0.1", 6);
  const protocolVault = await ethers.getContractAt(
    "ProtocolVault",
    deployment[env].protocolVault
  )
  // Define the parameters
  const depositParams = {
    payloadType: 0, //LP Deposit
    receiver: sender.address,
    token: config[currentNetwork].USDC,
    amount: value,
    brokerHash: orderlyHash
  };
  // console.log("Deposit Params: ", depositParams)

  //approve
  const token = await ethers.getContractAt("IERC20", config[currentNetwork].USDC);
  tx = await token.approve(deployment[env].protocolVault, ethers.MaxUint256);
  await tx.wait()
  console.log("Approve done")

  //get lz fee
  const nativeFee = await protocolVault.quoteOperation();
  //console.log("Native Fee: ", nativeFee.toString())
  //deposit
  // const nativeFee = 1190048;
  //https://sepolia.etherscan.io/tx/0x3d3ddea4f139b7e234ae6d701d792dd6ab095cc44bf6f8f7a50c5e15a8d98dca
  tx = await protocolVault.deposit(depositParams, { value: nativeFee.toString() }); // Replace with actual value if needed
  await tx.wait()
  console.log("Deposit done with tx:", tx.hash)
}

main()


