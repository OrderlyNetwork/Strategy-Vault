const { ethers } = require("hardhat")
const fs = require("fs");
const path = require('path');
const FactoryPath = path.join(__dirname, './factory.json');
const FactoryArtifact = JSON.parse(fs.readFileSync(FactoryPath, 'utf8'));
const deployment = require('../../deployment.json');

async function main() {
    //!need to change with your env
    const env = "mainnet"

    const owner = deployment[env].owner;
    const constructorArgs = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address"],
        [owner]
    );

    //final bytecode
    const bytecode = ethers.concat([
        FactoryArtifact.bytecode,
        constructorArgs
    ]);

    console.log(bytecode);
}

main()
