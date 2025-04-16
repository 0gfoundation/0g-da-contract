import { task, types } from "hardhat/config";
import { CONTRACTS, getTypedContract, transact } from "../utils/utils";

task("entrance:setblobprice", "set blob price")
    .addParam("price", "blob price", undefined, types.string, false)
    .addParam("execute", "send transaction or not", false, types.boolean, true)
    .setAction(async (args: { price: string; execute: boolean }, hre) => {
        const entrance_ = await getTypedContract(hre, CONTRACTS.DAEntrance);
        await transact(entrance_, "setBlobPrice", [BigInt(args.price)], args.execute);
    });

task("entrance:settreasury", "set treasury")
    .addParam("treasury", "treasury", undefined, types.string, false)
    .addParam("execute", "send transaction or not", false, types.boolean, true)
    .setAction(async (args: { treasury: string; execute: boolean }, hre) => {
        const entrance_ = await getTypedContract(hre, CONTRACTS.DAEntrance);
        await transact(entrance_, "setTreasury", [args.treasury], args.execute);
    });

task("entrance:sync", "sync").setAction(async (_, hre) => {
    const entrance_ = await getTypedContract(hre, CONTRACTS.DAEntrance);
    await transact(entrance_, "syncFixedTimes", [1000], true);
});

task("entrance:show", "sync").setAction(async (_, hre) => {
    const entrance_ = await getTypedContract(hre, CONTRACTS.DAEntrance);
    console.log(`block height: ${await hre.ethers.provider.getBlockNumber()}`);
    console.log(`currentEpoch: ${await entrance_.currentEpoch()}`);
    console.log(`nextSampleHeight: ${await entrance_.nextSampleHeight()}`);
    console.log(`baseReward: ${await entrance_.baseReward()}`);
});

task("entrance:payments", "payments")
    .addParam("account", "account address", false, types.string, true)
    .setAction(async (taskArgs: { account: string }, hre) => {
        const entrance_ = await getTypedContract(hre, CONTRACTS.DAEntrance);
        console.log(hre.ethers.formatEther(await entrance_.payments(taskArgs.account)));
        console.log(hre.ethers.formatEther(await hre.ethers.provider.getBalance(await entrance_.getAddress())));
    });

task("entrance:withdraw", "payments")
    .addParam("account", "account address", false, types.string, true)
    .setAction(async (taskArgs: { account: string }, hre) => {
        const entrance_ = await getTypedContract(hre, CONTRACTS.DAEntrance);
        console.log(hre.ethers.formatEther(await entrance_.payments(taskArgs.account)));
        const receipt = await (await entrance_.withdrawPayments(taskArgs.account)).wait();
        console.log(`claimed with tx: ${receipt?.hash}`);
        console.log(hre.ethers.formatEther(await entrance_.payments(taskArgs.account)));
        console.log(hre.ethers.formatEther(await hre.ethers.provider.getBalance(await entrance_.getAddress())));
    });
