import { Address, beginCell, Cell, Contract, contractAddress, ContractProvider, Sender, SendMode } from '@ton/core';

export type ElectorConfig = {};

export function electorConfigToCell(config: ElectorConfig): Cell {
    return beginCell().endCell();
}

export class Elector implements Contract {
    constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {}

    static createFromAddress(address: Address) {
        return new Elector(address);
    }

    static createFromConfig(config: ElectorConfig, code: Cell, workchain = 0) {
        const data = electorConfigToCell(config);
        const init = { code, data };
        return new Elector(contractAddress(workchain, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        });
    }
}
