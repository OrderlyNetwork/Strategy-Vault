const { ethers } = require("hardhat")

async function main() {
    const ProtocolVault = await ethers.getContractFactory("ProtocolVault");
    const proxy_bytecode = (await ethers.getContractFactory("ERC1967Proxy")).bytecode;
    
    
    const initializeData = ProtocolVault.interface.encodeFunctionData(
        "initialize",
        []
    );
    
    const implAddr = "";
    const constructorArgs = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "bytes"],
        [implAddr, initializeData]
    );
    console.log(constructorArgs);

    //final bytecode
    const bytecode = ethers.concat([
        proxy_bytecode,
        constructorArgs
    ]);

    //Deploy contract by factory
    const salt = ethers.ZeroHash;
    factoryAddr = "0x52f1795B4B0c15877805c8C90cA7D6E2567aB805"
    const contractFactory = await ethers.getContractAt(
        "ContractFactory",
        addfactoryAddrress
    )
    const tx = await contractFactory.deploy(salt,bytecode)
    await tx.wait()
    console.log("Contract deployed Done")
}

main()
