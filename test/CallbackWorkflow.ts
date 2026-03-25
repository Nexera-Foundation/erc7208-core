import assert from "node:assert/strict";
import { describe, it, beforeEach, afterEach } from "node:test";
import { network } from "hardhat";
import {
    encodeAbiParameters,
    parseAbiParameters,
    toFunctionSelector,
    decodeAbiParameters,
} from "viem";
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import DataPointRegistryModule from "../ignition/modules/DataPointRegistry.js";
import MinimalisticDataIndexModule from "../ignition/modules/MinimalisticDataIndex.js";

const SampleCallbackDataObjectModule = buildModule("SampleCallbackDataObject", (m) => {
    const dataObject = m.contract("SampleCallbackDataObject");
    return { dataObject };
});

const MockCallbackHandlerModule = buildModule("MockCallbackHandler", (m) => {
    const handler = m.contract("MockCallbackHandler");
    return { handler };
});

const REGISTER_SELECTOR = toFunctionSelector(
    "registerCallback(address,uint256,bytes)",
);
const GET_HANDLERS_SELECTOR = toFunctionSelector(
    "getCallbackHandlers()",
);
const EXECUTE_SELECTOR = toFunctionSelector("execute(uint256,bytes)");

const ALL_OPERATIONS = 2n ** 256n - 1n;

describe("Callback Workflow", async function () {
    const { viem, ignition, networkHelpers } = await network.connect();
    const [deployer, dpOwner, dataManager, unauthorized] =
        await viem.getWalletClients();
    let snap: Awaited<ReturnType<typeof networkHelpers.takeSnapshot>>;

    const { registry } = await ignition.deploy(DataPointRegistryModule);
    const { dataObject } = await ignition.deploy(SampleCallbackDataObjectModule);
    const { dataIndex } = await ignition.deploy(MinimalisticDataIndexModule);
    const { handler } = await ignition.deploy(MockCallbackHandlerModule);

    beforeEach(async function () {
        snap = await networkHelpers.takeSnapshot();
    });

    afterEach(async function () {
        snap.restore();
    });

    async function setupDpWithDm(): Promise<`0x${string}`> {
        const dp = (
            await registry.simulate.allocate([dpOwner.account.address])
        ).result;
        await registry.write.allocate([dpOwner.account.address]);
        await dataObject.write.setDataIndexImplementation(
            [dp, dataIndex.address],
            { account: dpOwner.account },
        );
        await dataIndex.write.allowDataManager(
            [dp, dataManager.account.address, true],
            { account: dpOwner.account },
        );
        return dp;
    }

    it("register callback handler and trigger it via execute", async () => {
        const dp = await setupDpWithDm();

        // Register the callback handler with ALL_OPERATIONS mask
        const registerData = encodeAbiParameters(
            parseAbiParameters("address, uint256, bytes"),
            [handler.address, ALL_OPERATIONS, "0x"],
        );
        await dataIndex.write.write(
            [dataObject.address, dp, REGISTER_SELECTOR, registerData],
            { account: dataManager.account },
        );

        // Verify registered handler is visible via getCallbackHandlers read
        const readResult = await dataObject.read.read([
            dp,
            GET_HANDLERS_SELECTOR,
            "0x",
        ]);
        const [handlers, masks] = decodeAbiParameters(
            parseAbiParameters("address[], uint256[]"),
            readResult,
        );
        assert.equal(handlers.length, 1);
        assert.equal(handlers[0].toLowerCase(), handler.address.toLowerCase());
        assert.equal(masks[0], ALL_OPERATIONS);

        // Execute a task — should trigger the callback handler
        const executeData = encodeAbiParameters(
            parseAbiParameters("uint256, bytes"),
            [1n, "0x1234"],
        );
        await dataIndex.write.write(
            [dataObject.address, dp, EXECUTE_SELECTOR, executeData],
            { account: dataManager.account },
        );

        // Verify handler was called
        const count = await handler.read.callCount();
        assert.equal(count, 1n);
    });

    it("handler with non-matching bitmask is not called", async () => {
        const dp = await setupDpWithDm();

        // Register handler with mask=1 (only matches task bit 0)
        const registerData = encodeAbiParameters(
            parseAbiParameters("address, uint256, bytes"),
            [handler.address, 1n, "0x"],
        );
        await dataIndex.write.write(
            [dataObject.address, dp, REGISTER_SELECTOR, registerData],
            { account: dataManager.account },
        );

        // Execute with task=2 (bit 1) — should NOT match mask=1 (bit 0)
        const executeData = encodeAbiParameters(
            parseAbiParameters("uint256, bytes"),
            [2n, "0x1234"],
        );
        await dataIndex.write.write(
            [dataObject.address, dp, EXECUTE_SELECTOR, executeData],
            { account: dataManager.account },
        );

        // Verify handler was NOT called
        const count = await handler.read.callCount();
        assert.equal(count, 0n);
    });
});
