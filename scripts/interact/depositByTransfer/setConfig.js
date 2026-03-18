const { ethers } = require("hardhat");
const deployment = require("../../../deployment/deployment.json");
const depositInfo = require("../../../deployment/depositBytransfer.json");

async function main() {
	const env = "dev";
	const factoryAddress = depositInfo[env].depositFactory;
	const dexOperator = deployment[env].dex_operator;

	const [signer] = await ethers.getSigners();
	const factory = await ethers.getContractAt("DepositFactory", factoryAddress);

	console.log(`env: ${env}`);
	console.log(`network: ${(await ethers.provider.getNetwork()).name}`);
	console.log(`signer: ${signer.address}`);
	console.log(`operator: ${dexOperator}`);

	//set operator 
	tx = await factory.setOperator(dexOperator);
	await tx.wait();
	console.log(`new operator: ${newOperator}`);
}

main().catch((error) => {
	console.error(error);
	process.exit(1);
});
