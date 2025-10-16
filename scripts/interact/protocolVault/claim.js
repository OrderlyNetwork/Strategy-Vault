const { ethers } = require("hardhat");
const deployment = require("../../../deployment/deployment.json");
const config = require("../../../config.json");

async function main() {
    // !Adjust these for your environment
    const env = process.env.ENV || "qa"; 
    const currentNetwork = hre.network.name;
    const [sender] = await ethers.getSigners();

    const protocolVault = await ethers.getContractAt(
        "ProtocolVault",
        deployment[env].protocolVault
    );

    const roleType = 0;
    const token = config[currentNetwork].USDC;
    const id = "0xf9fdd8648d22ef32e665f03249fe52804bc181cca3a98e3a16d18b41e34bc8d1"
    const brokerHash = "0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b";

    const ccFee = await protocolVault.crossChainFee(id);
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

    const tx = await protocolVault.claimWithFee(claimParams, { value: ccFee });
    const receipt = await tx.wait();
    console.log("Claim tx hash:", receipt.hash);
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});


