import { task, types } from "hardhat/config";
import { CONTRACTS, getTypedContract, transact } from "../utils/utils";

task("entrance:setblobprice", "set blob price")
    .addParam("price", "blob price", "", types.string, false)
    .addParam("execute", "send transaction or not", false, types.boolean, true)
    .setAction(async (args: { price: string; execute: boolean }, hre) => {
        const entrance_ = await getTypedContract(hre, CONTRACTS.DAEntrance);
        await transact(entrance_, "setBlobPrice", [BigInt(args.price)], args.execute);
    });

task("entrance:settreasury", "set treasury")
    .addParam("treasury", "treasury", "", types.string, false)
    .addParam("execute", "send transaction or not", false, types.boolean, true)
    .setAction(async (args: { treasury: string; execute: boolean }, hre) => {
        const entrance_ = await getTypedContract(hre, CONTRACTS.DAEntrance);
        await transact(entrance_, "setTreasury", [args.treasury], args.execute);
    });
