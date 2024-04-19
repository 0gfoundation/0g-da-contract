import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getConfig } from "../config";
import { CONTRACTS, deployInBeaconProxy, getTypedContract } from "../utils/utils";

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const config = getConfig(hre.network.name);

    await deployInBeaconProxy(hre, CONTRACTS.DAEntrance);

    const entrance_ = await getTypedContract(hre, CONTRACTS.DAEntrance);

    // initialize
    console.log(`initializing ${CONTRACTS.DAEntrance.name}..`);
    const registry_ = await getTypedContract(hre, CONTRACTS.DARegistry);
    if (!(await entrance_.initialized())) {
        await (await entrance_.initialize(config.addressBook, await registry_.getAddress())).wait();
    }
};

deploy.tags = [CONTRACTS.DAEntrance.name, "prod"];
deploy.dependencies = [CONTRACTS.DARegistry.name];
export default deploy;
