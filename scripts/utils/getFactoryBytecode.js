const { ethers } = require("hardhat")
const fs = require("fs");
const path = require('path');
const FactoryPath = path.join(__dirname, './factory.json');
const FactoryArtifact = JSON.parse(fs.readFileSync(FactoryPath, 'utf8'));

async function main() {
    const [owner] = await ethers.getSigners();

    const constructorArgs = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address"],
        [owner.address]
    );

    //final bytecode
    const bytecode = ethers.concat([
        FactoryArtifact.bytecode,
        constructorArgs
    ]);

    console.log(bytecode);
}

main()
