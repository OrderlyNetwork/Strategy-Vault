import { HardhatUserConfig, vars } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "./tasks/deploy.js";

const config: HardhatUserConfig = {
  solidity: "0.8.26",
};


const PRIVATE_KEY = vars.get("PRIVATE_KEY");

module.exports = {
  solidity: {
    version: "0.8.27",
    settings: {
      optimizer: {
        enabled: true,
        runs: 10000000,
      },
    },
  },
  networks: {
    mainnet: {
      url: "https://eth-mainnet.alchemyapi.io/v2/ygq0_STO_nrASY4_eq3I1JMyY1aLiViw",
      accounts: [PRIVATE_KEY],
    },
    bsc: {
      url: "https://bsc-dataseed4.ninicoin.io",
      accounts: [PRIVATE_KEY],
    },
    polygon: {
      url: "https://polygon-mainnet.g.alchemy.com/v2/xW-oS8VD9ND03JvtAj-C1kPvvGNud8zo",
      accounts: [PRIVATE_KEY],
    },
    avax: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      accounts: [PRIVATE_KEY],
    },
    arb: {
      url: "https://arb1.arbitrum.io/rpc",
      accounts: [PRIVATE_KEY],
    },
    op: {
      url: "https://optimism.llamarpc.com",
      accounts: [PRIVATE_KEY],
    },
    base: {
      url: "https://mainnet.base.org",
      accounts: [PRIVATE_KEY],
    },
    sepolia: {
      url: "https://gateway.tenderly.co/public/sepolia",
      accounts: [PRIVATE_KEY],
    },
    orderly_sepolia: {
      url: "https://testnet-rpc.orderly.org",
      accounts: [PRIVATE_KEY],
    },
    linea: {
      url: "https://rpc.linea.build/",
      accounts: [PRIVATE_KEY],
    },
    scroll: {
      url: "https://rpc.scroll.io/",
      accounts: [PRIVATE_KEY],
    },
    manta: {
      url: "https://pacific-rpc.manta.network/http",
      accounts: [PRIVATE_KEY],
    },
    arb_sepolia: {
      url: "https://gateway.tenderly.co/public/sepolia",
      accounts: [PRIVATE_KEY],
    }
  },
  etherscan: {
    apiKey: {
      sepolia: 'UFDT2P2RSDHXGX1TUG1RJXAHPQS26GZ6I6'
    }
  }
};

export default config;
