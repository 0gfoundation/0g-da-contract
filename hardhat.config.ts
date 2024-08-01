import "@nomicfoundation/hardhat-chai-matchers";
import "@nomicfoundation/hardhat-ethers";
import "@openzeppelin/hardhat-upgrades";
import "@typechain/hardhat";
import "hardhat-abi-exporter";
import "hardhat-deploy";
import "hardhat-deploy-ethers";
import "hardhat-gas-reporter";
import "hardhat-interface-generator";
import { HardhatUserConfig, HttpNetworkUserConfig } from "hardhat/types";
import "solidity-coverage";

// environment configs
import dotenv from "dotenv";
dotenv.config();
const { NODE_URL, DEPLOYER_KEY, ETHERSCAN_API_KEY } = process.env;

import "./src/tasks/access";
import "./src/tasks/entrance";
import "./src/tasks/example";
import "./src/tasks/upgrade";

// 0xa223d305bc8147a75761f7f72f983e5eef867bd4
const REMOVED_DEPLOYER_IDENTIFIER = "REMOVED_REMOVED_DEPLOYER_IDENTIFIER_PRIVATE_KEY";

const userConfig: HttpNetworkUserConfig = {
    accounts: [DEPLOYER_KEY ? DEPLOYER_KEY : REMOVED_DEPLOYER_IDENTIFIER],
};

const config: HardhatUserConfig = {
    paths: {
        artifacts: "build/artifacts",
        cache: "build/cache",
        sources: "contracts",
        deploy: "src/deploy",
    },
    solidity: {
        compilers: [
            {
                version: "0.8.16",
                settings: {
                    evmVersion: "london",
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
    },
    networks: {
        hardhat: {
            allowUnlimitedContractSize: true,
            allowBlocksWithSameTimestamp: true,
            blockGasLimit: 100000000,
            gas: 100000000,
        },
        zg: {
            ...userConfig,
            url: "http://0.0.0.0:8545",
        },
    },
    namedAccounts: {
        deployer: 0,
    },
    mocha: {
        timeout: 2000000,
    },
    verify: {
        etherscan: {
            apiKey: ETHERSCAN_API_KEY,
        },
    },
    gasReporter: {
        enabled: process.env.REPORT_GAS ? true : false,
    },
    abiExporter: {
        path: "./abis",
        runOnCompile: true,
        clear: true,
        flat: true,
        format: "json",
    },
};
if (NODE_URL && config.networks) {
    config.networks.custom = {
        ...userConfig,
        url: NODE_URL,
    };
}
export default config;
