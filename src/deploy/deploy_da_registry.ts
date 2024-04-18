import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { CONTRACTS, deployInBeaconProxy, getTypedContract } from "../utils/utils";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    await deployInBeaconProxy(hre, CONTRACTS.DARegistry);

    const registry_ = await getTypedContract(hre, CONTRACTS.DARegistry);

    // initialize
    console.log(`initializing ${CONTRACTS.DARegistry.name}..`);
    if (!(await registry_.initialized())) {
        await (await registry_.initialize()).wait();
    }
};

deploy.tags = [CONTRACTS.DARegistry.name, "prod"];
deploy.dependencies = [];
export default deploy;
