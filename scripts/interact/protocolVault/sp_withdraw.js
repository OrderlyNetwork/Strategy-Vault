const { ethers } = require("hardhat")
const deployment = require('../../../deployment.json');
const config = require('../../../config.json');


async function main() {
    //!need to change with your env
    const env = "dev";
    const currentNetwork = hre.network.name;
    const orderlyHash = "0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b"
    const value = ethers.parseUnits("0.008", 6);
    const protocolVault = await ethers.getContractAt(
        "ProtocolVault",
        deployment[env].protocolVault
    )
    const [sender] = await ethers.getSigners();
    const type = 3; //1 for LP Withdraw 3 for SP_WITHDRAW
    // Define the parameters
    const withdrawParams = {
        payloadType: type,
        token: config[currentNetwork].USDC,
        amount: value,
        brokerHash: orderlyHash
    };
    // console.log("Deposit Params: ", depositParams)

    //get lz fee
    const nativeFee = await protocolVault.quoteOperation(type, sender.address, withdrawParams.amount);
    console.log("Native Fee: ", nativeFee.toString())
    //deposit
    //const nativeFee = 1190048;
    tx = await protocolVault.withdraw(withdrawParams, { value: nativeFee.toString() });
    await tx.wait()
    console.log("Withdraw done with tx:", tx.hash)
}

main()


