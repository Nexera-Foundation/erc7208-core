import assert from "node:assert/strict";
import {describe, it, mock, before, beforeEach, afterEach} from "node:test";
import {network} from "hardhat";
import {anyValue} from "@nomicfoundation/hardhat-viem-assertions/predicates";
import type {GetContractReturnType} from "viem";
import DataPointRegistryModule from "../ignition/modules/DataPointRegistry.js";

describe("DataPointRegistry", async function () {
    const {viem, ignition, networkHelpers} = await network.connect();
    const publicClient = await viem.getPublicClient();
    const [user1, user2] = await viem.getWalletClients();
    let snap: Awaited<ReturnType<typeof networkHelpers.takeSnapshot>>;

    let dataPointRegistry: any;

    before(async () => {
        const {registry} = await ignition.deploy(DataPointRegistryModule);
        dataPointRegistry = registry;
    });

    beforeEach(async function () {
        snap = await networkHelpers.takeSnapshot();
    });

    afterEach(async function () {
        snap.restore();
    });

    it("should create a new data point", async () => {
        const simulatedDataPoint = await dataPointRegistry.simulate.allocate([user1.account.address]);
        // Verify Event emitted matches DataPoint returned to the caller
        await viem.assertions.emitWithArgs(dataPointRegistry.write.allocate([user1.account.address]), dataPointRegistry, "DataPointAllocated", [
            simulatedDataPoint.result,
            (addr: string) => addr.toLowerCase() == user1.account.address,
        ]);
    });

    it("revert: NativeCoinDepositIsNotAccepted", async () => {
        await viem.assertions.revertWithCustomError(
            dataPointRegistry.write.allocate([user1.account.address], {value: 1n}),
            dataPointRegistry,
            "NativeCoinDepositIsNotAccepted"
        );
    });

    it("Owner of DataPoint should be its Admin by default", async () => {
        const simulatedDataPoint = await dataPointRegistry.simulate.allocate([user1.account.address]);
        await dataPointRegistry.write.allocate([user1.account.address]);
        assert.equal(await dataPointRegistry.read.isAdmin([simulatedDataPoint.result, user1.account.address]), true);
    });

    //TODO More tests
});
