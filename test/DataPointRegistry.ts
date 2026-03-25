import assert from "node:assert/strict";
import { describe, it, beforeEach, afterEach } from "node:test";
import { network } from "hardhat";
import DataPointRegistryModule from "../ignition/modules/DataPointRegistry.js";

describe("DataPointRegistry", async function () {
    const { viem, ignition, networkHelpers } = await network.connect();
    const [owner, user1, user2] = await viem.getWalletClients();
    let snap: Awaited<ReturnType<typeof networkHelpers.takeSnapshot>>;

    const { registry: dataPointRegistry } = await ignition.deploy(DataPointRegistryModule);

    beforeEach(async function () {
        snap = await networkHelpers.takeSnapshot();
    });

    afterEach(async function () {
        snap.restore();
    });

    describe("allocate", () => {
        it("should allocate a new DataPoint", async () => {
            const result = await dataPointRegistry.simulate.allocate([owner.account.address]);
            assert.notEqual(result.result, "0x0000000000000000000000000000000000000000000000000000000000000000");
        });

        it("should emit DataPointAllocated event", async () => {
            const simulatedDataPoint = await dataPointRegistry.simulate.allocate([owner.account.address]);
            await viem.assertions.emitWithArgs(
                dataPointRegistry.write.allocate([owner.account.address]),
                dataPointRegistry,
                "DataPointAllocated",
                [simulatedDataPoint.result, (addr: string) => addr.toLowerCase() === owner.account.address]
            );
        });

        it("should allocate different DataPoints each time", async () => {
            const dp1 = await dataPointRegistry.simulate.allocate([owner.account.address]);
            await dataPointRegistry.write.allocate([owner.account.address]);
            const dp2 = await dataPointRegistry.simulate.allocate([owner.account.address]);
            assert.notEqual(dp1.result, dp2.result);
        });

        it("should revert on zero address", async () => {
            await viem.assertions.revertWithCustomError(
                dataPointRegistry.write.allocate(["0x0000000000000000000000000000000000000000"]),
                dataPointRegistry,
                "InvalidOwnerAddress"
            );
        });

        it("should revert when sending native coin", async () => {
            await viem.assertions.revertWithCustomError(
                dataPointRegistry.write.allocate([owner.account.address], { value: 1n }),
                dataPointRegistry,
                "NativeCoinDepositIsNotAccepted"
            );
        });
    });

    describe("admin management", () => {
        it("owner should be admin by default", async () => {
            const dp = (await dataPointRegistry.simulate.allocate([owner.account.address])).result;
            await dataPointRegistry.write.allocate([owner.account.address]);
            assert.equal(await dataPointRegistry.read.isAdmin([dp, owner.account.address]), true);
        });

        it("should grant admin role", async () => {
            const dp = (await dataPointRegistry.simulate.allocate([owner.account.address])).result;
            await dataPointRegistry.write.allocate([owner.account.address]);
            await dataPointRegistry.write.grantAdminRole([dp, user1.account.address]);
            assert.equal(await dataPointRegistry.read.isAdmin([dp, user1.account.address]), true);
        });

        it("should revoke admin role", async () => {
            const dp = (await dataPointRegistry.simulate.allocate([owner.account.address])).result;
            await dataPointRegistry.write.allocate([owner.account.address]);
            await dataPointRegistry.write.grantAdminRole([dp, user1.account.address]);
            await dataPointRegistry.write.revokeAdminRole([dp, user1.account.address]);
            assert.equal(await dataPointRegistry.read.isAdmin([dp, user1.account.address]), false);
        });

        it("non-owner cannot grant admin role", async () => {
            const dp = (await dataPointRegistry.simulate.allocate([owner.account.address])).result;
            await dataPointRegistry.write.allocate([owner.account.address]);
            await viem.assertions.revertWithCustomError(
                dataPointRegistry.write.grantAdminRole([dp, user2.account.address], { account: user1.account }),
                dataPointRegistry,
                "InvalidDataPointOwner"
            );
        });
    });

    describe("ownership transfer", () => {
        it("should transfer ownership", async () => {
            const dp = (await dataPointRegistry.simulate.allocate([owner.account.address])).result;
            await dataPointRegistry.write.allocate([owner.account.address]);
            await dataPointRegistry.write.transferOwnership([dp, user1.account.address]);
            assert.equal(await dataPointRegistry.read.isAdmin([dp, user1.account.address]), true);
        });

        it("should clean old admins on transfer", async () => {
            const dp = (await dataPointRegistry.simulate.allocate([owner.account.address])).result;
            await dataPointRegistry.write.allocate([owner.account.address]);
            await dataPointRegistry.write.grantAdminRole([dp, user1.account.address]);
            await dataPointRegistry.write.transferOwnership([dp, user2.account.address]);

            assert.equal(await dataPointRegistry.read.isAdmin([dp, owner.account.address]), false);
            assert.equal(await dataPointRegistry.read.isAdmin([dp, user1.account.address]), false);
            assert.equal(await dataPointRegistry.read.isAdmin([dp, user2.account.address]), true);
        });

        it("non-owner cannot transfer ownership", async () => {
            const dp = (await dataPointRegistry.simulate.allocate([owner.account.address])).result;
            await dataPointRegistry.write.allocate([owner.account.address]);
            await viem.assertions.revertWithCustomError(
                dataPointRegistry.write.transferOwnership([dp, user2.account.address], { account: user1.account }),
                dataPointRegistry,
                "InvalidDataPointOwner"
            );
        });
    });
});
