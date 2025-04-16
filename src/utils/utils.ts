import { FACTORY_POSTFIX } from "@typechain/ethers-v6/dist/common";
import {
    BaseContract,
    BigNumberish,
    ContractFactory,
    ContractRunner,
    encodeBytes32String,
    ethers,
    parseUnits,
    Signer,
} from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";

// We use the Typechain factory class objects to fill the `CONTRACTS` mapping. These objects are used
// by hardhat-deploy to locate compiled contract artifacts. However, an exception occurs if we import
// from Typechain files before they are generated. To avoid this, we follow a two-step process:
//
// 1. We import the types at compile time to ensure type safety. Hardhat does not report an error even
// if these files are not yet generated, as long as the "--typecheck" command-line argument is not used.
import * as TypechainTypes from "../../typechain-types";
// 2. We import the values at runtime and silently ignore any exceptions.
export let Factories = {} as typeof TypechainTypes;
try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    Factories = require("../../typechain-types") as typeof TypechainTypes;
} catch (err) {
    // ignore
}

// const ERC1967PROXY = "ERC1967Proxy";
export const UPGRADEABLE_BEACON = "UpgradeableBeacon";
export const BEACON_PROXY = "BeaconProxy";
export const DEFAULT_ADMIN_ROLE = "0x0000000000000000000000000000000000000000000000000000000000000000";
export const MINTER_ROLE = ethers.id("MINTER_ROLE");
export const PAUSER_ROLE = ethers.id("PAUSER_ROLE");
export const SPENDER_ROLE = ethers.id("SPENDER_ROLE");
export const VESTING_ROLE = ethers.id("VESTING_ROLE");
export const PERP_DOMAIN = encodeBytes32String("perpDomain");
export const MARGIN_DOMAIN = encodeBytes32String("marginDomain");
export const UNIT = 10n ** 18n;

export function validateError(e: unknown, msg: string) {
    if (e instanceof Error) {
        if (!e.toString().includes(msg)) {
            throw Error(`unexpected error: ${String(e)}`);
        }
    } else {
        throw Error(`unexpected error: ${String(e)}`);
    }
}

export function mul_D(x: BigNumberish, y: BigNumberish) {
    return (BigInt(x) * BigInt(y)) / UNIT;
}

export function div_D(x: BigNumberish, y: BigNumberish) {
    return (BigInt(x) * UNIT) / BigInt(y);
}

export function diff_D(x: BigNumberish, y: BigNumberish) {
    const diff = BigInt(x) - BigInt(y);
    return diff >= 0 ? diff : -diff;
}

export function tokenOf(x: string | number, decimals: number) {
    if (typeof x === "string") {
        return parseUnits(x, decimals);
    } else if (Number.isSafeInteger(x)) {
        return BigInt(x) * 10n ** BigInt(decimals);
    } else {
        throw Error(`unsafe convertion from number ${x} to bigint`);
    }
}

interface TypechainFactory<T> {
    new (...args: ConstructorParameters<typeof ContractFactory>): ContractFactory;
    connect: (address: string, runner?: ContractRunner | null) => T;
}

class ContractMeta<T> {
    factory: TypechainFactory<T>;
    /** Deployment name */
    name: string;

    constructor(factory: TypechainFactory<T>, name?: string) {
        this.factory = factory;
        this.name = name ?? this.contractName();
    }

    contractName() {
        // this.factory is undefined when the typechain files are not generated yet
        // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
        return this.factory?.name.slice(0, -FACTORY_POSTFIX.length);
    }
}

export const CONTRACTS = {
    DAEntrance: new ContractMeta(Factories.DAEntrance__factory),
    DARegistry: new ContractMeta(Factories.DARegistry__factory),
} as const;

type GetContractTypeFromContractMeta<F> = F extends ContractMeta<infer C> ? C : never;

type AnyContractType = GetContractTypeFromContractMeta<(typeof CONTRACTS)[keyof typeof CONTRACTS]>;

export type AnyContractMeta = ContractMeta<AnyContractType>;

// Ensure at compile time that all values in `CONTRACTS` conform to the `ContractMeta` interface
// eslint-disable-next-line @typescript-eslint/no-unused-vars
const CONTRACTS_TYPE_CHECK: Readonly<Record<string, ContractMeta<BaseContract>>> = CONTRACTS;

export async function deployDirectly(
    hre: HardhatRuntimeEnvironment,
    contract: ContractMeta<unknown>,
    args: unknown[] = []
) {
    const { deployments, getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    // deploy implementation
    await deployments.deploy(contract.name, {
        from: deployer,
        contract: contract.contractName(),
        args: args,
        log: true,
    });
}

export async function deployInBeaconProxy(
    hre: HardhatRuntimeEnvironment,
    contract: ContractMeta<unknown>,
    args: unknown[] = []
) {
    const { deployments, getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    // deploy implementation
    await deployments.deploy(`${contract.name}Impl`, {
        from: deployer,
        contract: contract.contractName(),
        args: args,
        log: true,
    });
    const implementation = await hre.ethers.getContract(`${contract.name}Impl`);
    // deploy beacon
    await deployments.deploy(`${contract.name}Beacon`, {
        from: deployer,
        contract: UPGRADEABLE_BEACON,
        args: [await implementation.getAddress()],
        log: true,
    });
    const beacon = await hre.ethers.getContract(`${contract.name}Beacon`);
    // deploy proxy
    await deployments.deploy(contract.name, {
        from: deployer,
        contract: BEACON_PROXY,
        args: [await beacon.getAddress(), []],
        log: true,
    });
}

export async function getTypedContract<T>(
    hre: HardhatRuntimeEnvironment,
    contract: ContractMeta<T>,
    signer?: Signer | string
) {
    const address = await (await hre.ethers.getContract(contract.name)).getAddress();
    if (signer === undefined) {
        signer = (await hre.getNamedAccounts()).deployer;
    }
    if (typeof signer === "string") {
        signer = await hre.ethers.getSigner(signer);
    }
    return contract.factory.connect(address, signer);
}

export async function transact(contract: BaseContract, methodName: string, params: unknown[], execute: boolean) {
    if (execute) {
        await (await contract.getFunction(methodName).send(...params)).wait();
    } else {
        console.log(`to: ${await contract.getAddress()}`);
        console.log(`func: ${contract.interface.getFunction(methodName)?.format()}`);
        // eslint-disable-next-line @typescript-eslint/no-unsafe-return
        console.log(`params: ${JSON.stringify(params, (_, v) => (typeof v === "bigint" ? v.toString() : v))}`);
        console.log(`data: ${contract.interface.encodeFunctionData(methodName, params)}`);
    }
}

export async function getRawDeployment(
    hre: HardhatRuntimeEnvironment,
    contractName: string,
    key: string,
    args: unknown[] = [],
    nonce: number = 0
) {
    const instance = await hre.ethers.getContractFactory(contractName);
    const data = (await instance.getDeployTransaction(...args)).data;

    const wallet = new ethers.Wallet(key);

    const tx = {
        type: 0,
        nonce: nonce,
        gasPrice: ethers.parseUnits("100", "gwei"),
        gasLimit: 1000000n,
        to: null,
        value: 0,
        data: data,
        chainId: 0n,
    };

    const signedTx = await wallet.signTransaction(ethers.Transaction.from(tx));

    return signedTx;
}
