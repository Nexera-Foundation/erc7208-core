import assert from "node:assert/strict";
import { describe, it, before, beforeEach, afterEach } from "node:test";
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

describe("Access Control", async function () {
    const { viem, ignition, networkHelpers } = await network.connect();
    const [deployer, admin1, admin2, dm1, dm2, outsider] =
        await viem.getWalletClients();
    let snap: Awaited<ReturnType<typeof networkHelpers.takeSnapshot>>;

    let registry: any;
    let dataObject: any;
    let dataIndex: any;

    before(async () => {
        registry = (await ignition.deploy(DataPointRegistryModule)).registry;
        dataObject = (await ignition.deploy(SampleDataObjectModule)).dataObject;
        dataIndex = (await ignition.deploy(MinimalisticDataIndexModule))
            .dataIndex;
    });

    beforeEach(async function () {
        snap = await networkHelpers.takeSnapshot();
    });

    afterEach(async function () {
        snap.restore();
    });

    /**
     * Helper: allocate a DataPoint owned by the given account.
     */
    async function allocateDP(
        owner: (typeof admin1),
    ): Promise<`0x${string}`> {
        const dp = (
            await registry.simulate.allocate([owner.account.address])
        ).result;
        await registry.write.allocate([owner.account.address]);
        return dp;
    }

    /**
     * Helper: wire a DataPoint to the DataObject via DataIndex.
     */
    async function wireDP(
        dp: `0x${string}`,
        admin: (typeof admin1),
    ): Promise<void> {
        await dataObject.write.setDataIndexImplementation(
            [dp, dataIndex.address],
            { account: admin.account },
        );
    }

    it("multiple admins can each approve different DMs", async () => {
        // admin1 allocates DP and grants admin2
        const dp = await allocateDP(admin1);
        await wireDP(dp, admin1);
        await registry.write.grantAdminRole(
            [dp, admin2.account.address],
            { account: admin1.account },
        );

        // admin1 approves dm1
        await dataIndex.write.allowDataManager(
            [dp, dm1.account.address, true],
            { account: admin1.account },
        );

        // admin2 approves dm2
        await dataIndex.write.allowDataManager(
            [dp, dm2.account.address, true],
            { account: admin2.account },
        );

        // Both DMs should be approved
        assert.equal(
            await dataIndex.read.isApprovedDataManager([dp, dm1.account.address]),
            true,
        );
        assert.equal(
            await dataIndex.read.isApprovedDataManager([dp, dm2.account.address]),
            true,
        );

        // Both can write
        const setData1 = encodeAbiParameters(parseAbiParameters("uint256"), [10n]);
        await dataIndex.write.write(
            [dataObject.address, dp, SET_SELECTOR, setData1],
            { account: dm1.account },
        );
        const result1 = await dataIndex.read.read([
            dataObject.address, dp, VALUE_SELECTOR, "0x",
        ]);
        const [value1] = decodeAbiParameters(parseAbiParameters("uint256"), result1);
        assert.equal(value1, 10n);

        const setData2 = encodeAbiParameters(parseAbiParameters("uint256"), [20n]);
        await dataIndex.write.write(
            [dataObject.address, dp, SET_SELECTOR, setData2],
            { account: dm2.account },
        );
        const result2 = await dataIndex.read.read([
            dataObject.address, dp, VALUE_SELECTOR, "0x",
        ]);
        const [value2] = decodeAbiParameters(parseAbiParameters("uint256"), result2);
        assert.equal(value2, 20n);
    });

    it("revoking admin invalidates their DM approvals", async () => {
        // admin1 allocates DP and grants admin2
        const dp = await allocateDP(admin1);
        await wireDP(dp, admin1);
        await registry.write.grantAdminRole(
            [dp, admin2.account.address],
            { account: admin1.account },
        );

        // admin2 approves dm1
        await dataIndex.write.allowDataManager(
            [dp, dm1.account.address, true],
            { account: admin2.account },
        );

        // dm1 should be approved
        assert.equal(
            await dataIndex.read.isApprovedDataManager([dp, dm1.account.address]),
            true,
        );

        // admin1 revokes admin2
        await registry.write.revokeAdminRole(
            [dp, admin2.account.address],
            { account: admin1.account },
        );

        // dm1's approval should now be invalid (approved by a revoked admin)
        assert.equal(
            await dataIndex.read.isApprovedDataManager([dp, dm1.account.address]),
            false,
        );

        // dm1 cannot write anymore
        const setData = encodeAbiParameters(parseAbiParameters("uint256"), [99n]);
        await viem.assertions.revertWithCustomError(
            dataIndex.write.write(
                [dataObject.address, dp, SET_SELECTOR, setData],
                { account: dm1.account },
            ),
            dataIndex,
            "DataManagerNotApproved",
        );
    });

    it("outsider cannot approve DataManagers", async () => {
        const dp = await allocateDP(admin1);
        await wireDP(dp, admin1);

        // outsider tries to approve dm1 — should revert
        await viem.assertions.revertWithCustomError(
            dataIndex.write.allowDataManager(
                [dp, dm1.account.address, true],
                { account: outsider.account },
            ),
            dataIndex,
            "InvalidDataPointAdmin",
        );
    });

    it("DM approved for one DP cannot write to another DP", async () => {
        // Allocate two DataPoints
        const dp1 = await allocateDP(admin1);
        await wireDP(dp1, admin1);
        const dp2 = await allocateDP(admin1);
        await wireDP(dp2, admin1);

        // Approve dm1 only for dp1
        await dataIndex.write.allowDataManager(
            [dp1, dm1.account.address, true],
            { account: admin1.account },
        );

        // dm1 can write to dp1
        const setData = encodeAbiParameters(parseAbiParameters("uint256"), [42n]);
        await dataIndex.write.write(
            [dataObject.address, dp1, SET_SELECTOR, setData],
            { account: dm1.account },
        );
        const result = await dataIndex.read.read([
            dataObject.address, dp1, VALUE_SELECTOR, "0x",
        ]);
        const [value] = decodeAbiParameters(parseAbiParameters("uint256"), result);
        assert.equal(value, 42n);

        // dm1 cannot write to dp2
        await viem.assertions.revertWithCustomError(
            dataIndex.write.write(
                [dataObject.address, dp2, SET_SELECTOR, setData],
                { account: dm1.account },
            ),
            dataIndex,
            "DataManagerNotApproved",
        );
    });

    it("ownership transfer + new admin flow", async () => {
        // admin1 allocates DP and approves dm1
        const dp = await allocateDP(admin1);
        await wireDP(dp, admin1);
        await dataIndex.write.allowDataManager(
            [dp, dm1.account.address, true],
            { account: admin1.account },
        );

        // dm1 is approved
        assert.equal(
            await dataIndex.read.isApprovedDataManager([dp, dm1.account.address]),
            true,
        );

        // Transfer ownership to admin2 (clears all admins including admin1)
        await registry.write.transferOwnership(
            [dp, admin2.account.address],
            { account: admin1.account },
        );

        // admin1 is no longer admin, so dm1's approval is invalidated
        assert.equal(
            await dataIndex.read.isApprovedDataManager([dp, dm1.account.address]),
            false,
        );

        // admin2 can approve dm2
        await dataIndex.write.allowDataManager(
            [dp, dm2.account.address, true],
            { account: admin2.account },
        );
        assert.equal(
            await dataIndex.read.isApprovedDataManager([dp, dm2.account.address]),
            true,
        );

        // dm2 can write
        const setData = encodeAbiParameters(parseAbiParameters("uint256"), [77n]);
        await dataIndex.write.write(
            [dataObject.address, dp, SET_SELECTOR, setData],
            { account: dm2.account },
        );
        const result = await dataIndex.read.read([
            dataObject.address, dp, VALUE_SELECTOR, "0x",
        ]);
        const [val] = decodeAbiParameters(parseAbiParameters("uint256"), result);
        assert.equal(val, 77n);
    });

    it("reading through DataIndex does not require DM approval", async () => {
        // Setup a DP with dm1 approved, set a value
        const dp = await allocateDP(admin1);
        await wireDP(dp, admin1);
        await dataIndex.write.allowDataManager(
            [dp, dm1.account.address, true],
            { account: admin1.account },
        );

        const setData = encodeAbiParameters(parseAbiParameters("uint256"), [123n]);
        await dataIndex.write.write(
            [dataObject.address, dp, SET_SELECTOR, setData],
            { account: dm1.account },
        );

        // outsider (not a DM) can still read
        const result = await dataIndex.read.read([
            dataObject.address,
            dp,
            VALUE_SELECTOR,
            "0x",
        ]);
        const [value] = decodeAbiParameters(parseAbiParameters("uint256"), result);
        assert.equal(value, 123n);
    });
});
