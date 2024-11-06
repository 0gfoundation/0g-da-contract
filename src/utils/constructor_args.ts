import { CONTRACTS } from "./utils";

export function getConstructorArgs(_network: string, name: string): unknown[] {
    let args: unknown[] = [];
    switch (name) {
        case CONTRACTS.DAEntrance.name: {
            args = [];
            break;
        }
        default: {
            break;
        }
    }
    return args;
}
