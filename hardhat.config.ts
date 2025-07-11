import { HardhatUserConfig, vars } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "./tasks/deploy.js";
import "./tasks/config.js";
import "./tasks/check.js";
import "./tasks/transferOwnerShip.js";
import "./tasks/verify.js";
const config: HardhatUserConfig = {
  solidity: "0.8.26",
};


const PRIVATE_KEY = vars.get("PRIVATE_KEY");
const DEPLOY_KEY = vars.get("DEPLOY_KEY");

module.exports = {
  solidity: {
    version: "0.8.27",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
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
      accounts: [DEPLOY_KEY],
    },
    op: {
      url: "https://optimism.llamarpc.com",
      accounts: [DEPLOY_KEY],
    },
    op_sepolia: {
      url: "https://sepolia.optimism.io",
      accounts: [PRIVATE_KEY],
    },
    base: {
      url: "https://mainnet.base.org",
      accounts: [DEPLOY_KEY],
    },
    base_sepolia: {
      url: "https://sepolia.base.org",
      accounts: [PRIVATE_KEY],
    },
    sepolia: {
      url: "https://gateway.tenderly.co/public/sepolia",
      accounts: [PRIVATE_KEY],
    },
    orderly: {
      url: "https://rpc.orderly.network",
      accounts: [DEPLOY_KEY],
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
      url: "https://sepolia-rollup.arbitrum.io/rpc",
      accounts: [PRIVATE_KEY],
    },
    bsc_test: {
      url: "https://data-seed-prebsc-1-s2.bnbchain.org:8545",
      accounts: [PRIVATE_KEY],
    }
  },
  etherscan: {
    apiKey: {
      orderly_sepolia: '123',//not needed
      orderly: '123',//not needed
      sepolia: 'X2T8M83VFFCCPBAP646B7AB4XT263CRRXZ',
      arbitrumSepolia: 'PB64D51YKMIMAJNFP95R8BEXG8R6JB7R19',
      arbitrumOne: 'PB64D51YKMIMAJNFP95R8BEXG8R6JB7R19',
      op_sepolia: 'TZY1RU2T9BJE973MX6SB2FU2D6QZYWW8XN',
      baseSepolia: 'UGMXZBZXQHJQP1B5H6382Z7C8G9X7FDR6C',
      base: 'UGMXZBZXQHJQP1B5H6382Z7C8G9X7FDR6C',
      optimisticEthereum: 'TZY1RU2T9BJE973MX6SB2FU2D6QZYWW8XN',
      bscTestnet: 'A2WXW5P36IKUUB2CGJEC6WEXR4SQ5MRKKE'
    },
    customChains: [
      {
        network: "orderly_sepolia",
        chainId: 4460,
        urls: {
          apiURL: "https://testnet-explorer.orderly.org/api",
          browserURL: "https://testnet-explorer.orderly.org/",
        }
      },
      {
        network: "orderly",
        chainId: 291,
        urls: {
          apiURL: "https://explorer.orderly.network/api",
          browserURL: "https://explorer.orderly.network/",
        }
      },
      {
        network: "op_sepolia",
        chainId: 11155420,
        urls: {
          apiURL: "https://api-sepolia-optimistic.etherscan.io/api",
          browserURL: "https://sepolia-optimism.etherscan.io/",
        }
      }
    ]
  }
};

export default config;
