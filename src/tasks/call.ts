import { task } from "hardhat/config";
import { Factories } from "../utils/utils";

task("call:precompile", "call precompile contract").setAction(async (_, hre) => {
    const precompile = Factories.IDASigners__factory.connect(
        "0x0000000000000000000000000000000000001000",
        (await hre.ethers.getSigners())[0]
    );
    console.log(await precompile.epochNumber());
});
