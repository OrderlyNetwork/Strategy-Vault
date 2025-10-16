const { ethers } = require("hardhat");
const deployment = require("../../../deployment/deployment.json");
const config = require("../../../config.json");

async function main() {
  // Adjust these for your environment
  const env = process.env.ENV || "qa"; // qa | dev | prod
  const currentNetwork = hre.network.name;
  const [sender] = await ethers.getSigners();

  const protocolVault = await ethers.getContractAt(
    "ProtocolVault",
    deployment[env].protocolVault
  );

  // RoleType: 0 = LP, 1 = SP
  const roleType = Number(process.env.ROLE_TYPE || 0);

  // Broker hash (must match what was used when generating IDs on-chain)
  // Keep consistent with other scripts (lp_deposit.js)
  const brokerHash =
    process.env.BROKER_HASH ||
    "0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b";

  // Token to claim (USDC on current network)
  const token = process.env.TOKEN || config[currentNetwork].USDC;

  // Compute user id used by ProtocolVault.crossChainFee mapping
  // LP: keccak256(abi.encode(sender, brokerHash))
  // SP: keccak256(abi.encode(protocolVault, sender, brokerHash))
  const abiCoder = ethers.AbiCoder.defaultAbiCoder();
  const vaultAddress = protocolVault.target; // ethers v6
  const id =
    roleType === 0
      ? ethers.keccak256(
          abiCoder.encode(["address", "bytes32"], [sender.address, brokerHash])
        )
      : ethers.keccak256(
          abiCoder.encode(
            ["address", "address", "bytes32"],
            [vaultAddress, sender.address, brokerHash]
          )
        );

  const ccFee = await protocolVault.crossChainFee(id);
  console.log("User ID:", id);
  console.log("Cross-chain fee (wei):", ccFee.toString());

  if (ccFee === 0n) {
    console.log("No cross-chain fee recorded for this user. Nothing to claim.");
    return;
  }

  const claimParams = {
    roleType,
    token,
    brokerHash,
  };

  console.log("Claiming with params:", claimParams);
  const tx = await protocolVault.claimWithFee(claimParams, { value: ccFee });
  const receipt = await tx.wait();
  console.log("Claim tx hash:", receipt.hash);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});


