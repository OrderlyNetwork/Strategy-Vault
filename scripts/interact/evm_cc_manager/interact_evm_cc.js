const { ethers } = require("hardhat")
const deployment = require('../../../deployment.json');
const config = require('../../../config.json');
const endpointV2ABI = require("@layerzerolabs/lz-evm-protocol-v2/artifacts/contracts/EndpointV2.sol/EndpointV2.json").abi;

async function main() {
    //!need to change with your env
    const env = "qa";

    const VaultCrossChainManager = await ethers.getContractAt(
        "VaultCrossChainManager",
        deployment[env].crossChainManager
    )

    //set options
    // tx = await VaultCrossChainManager.setOptions(0, 120000, 0);
    // await tx.wait()
    // console.log("Option set LP deposit successfully")
    //console.log(await VaultCrossChainManager.peers(40200));
    
    const endpointv2 = await ethers.getContractAt(
        endpointV2ABI,
        "0x6EDCE65403992e310A62460808c4b910D972f10f"
    );
    console.log("endpointv2", endpointv2)
}

main()
