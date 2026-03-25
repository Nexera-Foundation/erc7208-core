import assert from "node:assert/strict";
import { describe, it, beforeEach, afterEach } from "node:test";
import { network } from "hardhat";
import {
    encodeAbiParameters,
    parseAbiParameters,
    toFunctionSelector,
    decodeAbiParameters,
} from "viem";
import DataPointRegistryModule from "../ignition/modules/DataPointRegistry.js";
import SampleDataObjectModule from "../ignition/modules/SampleDataObject.js";
import MinimalisticDataIndexModule from "../ignition/modules/MinimalisticDataIndex.js";

const VALUE_SELECTOR = toFunctionSelector("value()");
const SET_SELECTOR = toFunctionSelector("set(uint256)");
const INC_SELECTOR = toFunctionSelector("inc()");
const DEC_SELECTOR = toFunctionSelector("dec()");
const CAS_SELECTOR = toFunctionSelector("compareAndSet(uint256,uint256)");

describe("End-to-End Protocol Workflow", async function () {
    const { viem, ignition, networkHelpers } = await network.connect();
    const [deployer, dpOwner, dataManager, unauthorized] =
        await viem.getWalletClients();
    let snap: Awaited<ReturnType<typeof networkHelpers.takeSnapshot>>;

    const { registry } = await ignition.deploy(DataPointRegistryModule);
    const { dataObject } = await ignition.deploy(SampleDataObjectModule);
    const { dataIndex } = await ignition.deploy(MinimalisticDataIndexModule);

    beforeEach(async function () {
        snap = await networkHelpers.takeSnapshot();
    });

    afterEach(async function () {
        snap.restore();
    });

    /**
     * Helper: allocate a DataPoint, wire it to the DataObject via DataIndex,
     * and approve a DataManager. Returns the DataPoint.
     */
    async function setupDataPoint(
        owner: (typeof dpOwner),
        dm?: (typeof dataManager),
    ): Promise<`0x${string}`> {
        // 1. Allocate DataPoint
        const dp = (
            await registry.simulate.allocate([owner.account.address])
        ).result;
        await registry.write.allocate([owner.account.address]);

        // 2. Wire DataObject to DataIndex
        await dataObject.write.setDataIndexImplementation(
            [dp, dataIndex.address],
            { account: owner.account },
        );

        // 3. Approve DataManager if provided
        if (dm) {
            await dataIndex.write.allowDataManager(
                [dp, dm.account.address, true],
                { account: owner.account },
            );
        }

        return dp;
    }

    it("full workflow: allocate → wire → approve DM → write → read", async () => {
        const dp = await setupDataPoint(dpOwner, dataManager);

        // Write value through DataIndex as DataManager
        const setData = encodeAbiParameters(
            parseAbiParameters("uint256"),
            [42n],
        );
        await dataIndex.write.write(
            [dataObject.address, dp, SET_SELECTOR, setData],
            { account: dataManager.account },
        );

        // Read value back
        const result = await dataIndex.read.read([
            dataObject.address,
            dp,
            VALUE_SELECTOR,
            "0x",
        ]);
        const [value] = decodeAbiParameters(
            parseAbiParameters("uint256"),
            result,
        );
        assert.equal(value, 42n);
    });

    it("unauthorized DataManager cannot write", async () => {
        const dp = await setupDataPoint(dpOwner, dataManager);

        const setData = encodeAbiParameters(
            parseAbiParameters("uint256"),
            [99n],
        );

        // Unauthorized account should be rejected
        await viem.assertions.revertWithCustomError(
            dataIndex.write.write(
                [dataObject.address, dp, SET_SELECTOR, setData],
                { account: unauthorized.account },
            ),
            dataIndex,
            "DataManagerNotApproved",
        );
    });

    it("increment and decrement through full stack", async () => {
        const dp = await setupDataPoint(dpOwner, dataManager);

        // Set value to 10
        const setData = encodeAbiParameters(
            parseAbiParameters("uint256"),
            [10n],
        );
        await dataIndex.write.write(
            [dataObject.address, dp, SET_SELECTOR, setData],
            { account: dataManager.account },
        );

        // Increment
        await dataIndex.write.write(
            [dataObject.address, dp, INC_SELECTOR, "0x"],
            { account: dataManager.account },
        );

        // Decrement
        await dataIndex.write.write(
            [dataObject.address, dp, DEC_SELECTOR, "0x"],
            { account: dataManager.account },
        );

        // Value should still be 10
        const result = await dataIndex.read.read([
            dataObject.address,
            dp,
            VALUE_SELECTOR,
            "0x",
        ]);
        const [value] = decodeAbiParameters(
            parseAbiParameters("uint256"),
            result,
        );
        assert.equal(value, 10n);
    });

    it("compareAndSet succeeds on match and fails on mismatch", async () => {
        const dp = await setupDataPoint(dpOwner, dataManager);

        // Set initial value to 10
        const setData = encodeAbiParameters(
            parseAbiParameters("uint256"),
            [10n],
        );
        await dataIndex.write.write(
            [dataObject.address, dp, SET_SELECTOR, setData],
            { account: dataManager.account },
        );

        // CAS with correct expected value (10 → 20) should succeed
        const casSuccess = encodeAbiParameters(
            parseAbiParameters("uint256, uint256"),
            [10n, 20n],
        );
        await dataIndex.write.write(
            [dataObject.address, dp, CAS_SELECTOR, casSuccess],
            { account: dataManager.account },
        );

        // Value should now be 20
        const result1 = await dataIndex.read.read([
            dataObject.address,
            dp,
            VALUE_SELECTOR,
            "0x",
        ]);
        const [value1] = decodeAbiParameters(
            parseAbiParameters("uint256"),
            result1,
        );
        assert.equal(value1, 20n);

        // CAS with wrong expected value (10 → 30) should not change value
        const casFail = encodeAbiParameters(
            parseAbiParameters("uint256, uint256"),
            [10n, 30n],
        );
        await dataIndex.write.write(
            [dataObject.address, dp, CAS_SELECTOR, casFail],
            { account: dataManager.account },
        );

        // Value should still be 20
        const result2 = await dataIndex.read.read([
            dataObject.address,
            dp,
            VALUE_SELECTOR,
            "0x",
        ]);
        const [value2] = decodeAbiParameters(
            parseAbiParameters("uint256"),
            result2,
        );
        assert.equal(value2, 20n);
    });

    it("multiple DataPoints with independent state", async () => {
        // Allocate two DataPoints, both wired to same DataObject
        const dp1 = await setupDataPoint(dpOwner, dataManager);
        const dp2 = await setupDataPoint(dpOwner, dataManager);

        // Set different values for each DP
        const setData1 = encodeAbiParameters(
            parseAbiParameters("uint256"),
            [100n],
        );
        const setData2 = encodeAbiParameters(
            parseAbiParameters("uint256"),
            [200n],
        );

        await dataIndex.write.write(
            [dataObject.address, dp1, SET_SELECTOR, setData1],
            { account: dataManager.account },
        );
        await dataIndex.write.write(
            [dataObject.address, dp2, SET_SELECTOR, setData2],
            { account: dataManager.account },
        );

        // Read both — they should have independent values
        const result1 = await dataIndex.read.read([
            dataObject.address,
            dp1,
            VALUE_SELECTOR,
            "0x",
        ]);
        const result2 = await dataIndex.read.read([
            dataObject.address,
            dp2,
            VALUE_SELECTOR,
            "0x",
        ]);

        const [value1] = decodeAbiParameters(
            parseAbiParameters("uint256"),
            result1,
        );
        const [value2] = decodeAbiParameters(
            parseAbiParameters("uint256"),
            result2,
        );

        assert.equal(value1, 100n);
        assert.equal(value2, 200n);
    });
});
