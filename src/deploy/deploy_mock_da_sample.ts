import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const ethers = hre.ethers;
    const sampleABI = await ethers.getContractFactory("MockDASample");
    const sample = await sampleABI.deploy();
    console.log(`Deploy mock contract at ${await sample.getAddress()}`);
};

deploy.tags = ["MockDASample", "test"];
deploy.dependencies = [];
export default deploy;
