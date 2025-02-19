const { ethers } = require("hardhat")

async function main() {
    //test: 0x20A69D786Fe0C91fc95aD1361e4626a92065aE39
    let pv_ledger = "0x20A69D786Fe0C91fc95aD1361e4626a92065aE39"

    const pvLedger = await ethers.getContractAt(
        "ProtocolVaultLedger",
        pv_ledger
    )

    const periodId = 0;
    const vaultId = ethers.ZeroHash;

    //signature
    const strategyFundAssets = [
        {
            strategyProviderId: ethers.encodeBytes32String("strategy1"),
            totalAssets: 1000
        }
    ];

    const encodedParams = ethers.AbiCoder.defaultAbiCoder().encode(
        [
            "uint256",
            "bytes32",
            "tuple(bytes32 strategyProviderId, uint256 totalAssets)[]"
        ],
        [
            periodId,
            vaultId,
            strategyFundAssets
        ]
    );
    const messageHash = ethers.keccak256(encodedParams);

    const [signer] = await ethers.getSigners();  
    const signature = await signer.signMessage(ethers.getBytes(messageHash));

    tx = await pvLedger.updateStrategyFundAssets(periodId, vaultId, strategyFundAssets, signature);
    await tx.wait()
    console.log("updateStrategyFundAssets");
}

main()
