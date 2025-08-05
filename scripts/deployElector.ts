import { toNano } from '@ton/core';
import { Elector } from '../wrappers/Elector';
import { compile, NetworkProvider } from '@ton/blueprint';

export async function run(provider: NetworkProvider) {
    const elector = provider.open(Elector.createFromConfig({}, await compile('Elector')));

    await elector.sendDeploy(provider.sender(), toNano('0.05'));

    await provider.waitForDeploy(elector.address);

    // run methods on `elector`
}
