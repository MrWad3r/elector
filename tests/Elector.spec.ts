import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { Cell, toNano } from '@ton/core';
import { Elector } from '../wrappers/Elector';
import '@ton/test-utils';
import { compile } from '@ton/blueprint';

describe('Elector', () => {
    let code: Cell;

    beforeAll(async () => {
        code = await compile('Elector');
    });

    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let elector: SandboxContract<Elector>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();

        elector = blockchain.openContract(Elector.createFromConfig({}, code));

        deployer = await blockchain.treasury('deployer');

        const deployResult = await elector.sendDeploy(deployer.getSender(), toNano('0.05'));

        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: elector.address,
            deploy: true,
            success: true,
        });
    });

    it('should deploy', async () => {
        // the check is done inside beforeEach
        // blockchain and elector are ready to use
    });
});
