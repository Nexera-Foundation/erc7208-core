import assert from "node:assert/strict";
import { describe, it, before, beforeEach, afterEach } from "node:test";
import { network } from "hardhat";
import {
    keccak256,
    encodePacked,
    encodeAbiParameters,
    parseAbiParameters,
    pad,
    toHex,
    getAddress,
    toFunctionSelector,
} from "viem";
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import DataPointRegistryModule from "../ignition/modules/DataPointRegistry.js";
import MinimalisticDataIndexModule from "../ignition/modules/MinimalisticDataIndex.js";

const SampleDataObjectUpgradeableModule = buildModule("SampleDataObjectUpgradeable", (m) => {
    const deployer = m.getAccount(0);
    const impl = m.contract("SampleDataObjectUpgradeable");
    const initData = m.encodeFunctionCall(impl, "initialize", []);
    const proxy = m.contract("TestTransparentProxy", [impl, deployer, initData], { id: "proxy" });
    return { proxy, impl };
});

const SampleCallbackDataObjectUpgradeableModule = buildModule("SampleCallbackDataObjectUpgradeable", (m) => {
    const deployer = m.getAccount(0);
    const impl = m.contract("SampleCallbackDataObjectUpgradeable");
    const initData = m.encodeFunctionCall(impl, "initialize", []);
    const proxy = m.contract("TestTransparentProxy", [impl, deployer, initData], { id: "proxy" });
    return { proxy, impl };
});

const MockCallbackHandlerModule = buildModule("MockCallbackHandler", (m) => {
    const handler = m.contract("MockCallbackHandler");
    return { handler };
});

/**
 * Compute an ERC-7201 storage slot from a namespace string.
 * Formula: keccak256(abi.encode(uint256(keccak256(namespace)) - 1)) & ~bytes32(uint256(0xff))
 */
function computeERC7201Slot(namespace: string): `0x${string}` {
    const nsHash = keccak256(encodePacked(["string"], [namespace]));
    const decremented = BigInt(nsHash) - 1n;
    const encoded = encodeAbiParameters(parseAbiParameters("uint256"), [decremented]);
    const finalHash = keccak256(encoded);
    const masked = BigInt(finalHash) & ~0xffn;
    return pad(toHex(masked), { size: 32 }) as `0x${string}`;
}

const REGISTER_CALLBACK_SELECTOR = toFunctionSelector("registerCallback(address,uint256,bytes)");
const ALL_OPERATIONS = 2n ** 256n - 1n;

describe("ERC-7201 Storage Slot Verification", async function () {
    const { viem, ignition, networkHelpers } = await network.connect();
    const [deployer, dpOwner] = await viem.getWalletClients();
    const publicClient = await viem.getPublicClient();
    let snap: Awaited<ReturnType<typeof networkHelpers.takeSnapshot>>;

    let registry: any;
    let dataIndex: any;

    before(async () => {
        registry = (await ignition.deploy(DataPointRegistryModule)).registry;
        dataIndex = (await ignition.deploy(MinimalisticDataIndexModule)).dataIndex;
    });

    beforeEach(async function () {
        snap = await networkHelpers.takeSnapshot();
    });

    afterEach(async function () {
        snap.restore();
    });

    it("BaseDataObjectUpgradeable uses correct ERC-7201 slot for defaultDataIndex", async () => {
        // Deploy upgradeable DataObject behind a proxy
        const { proxy } = await ignition.deploy(SampleDataObjectUpgradeableModule);
        const dataObject = await viem.getContractAt("SampleDataObjectUpgradeable", proxy.address);

        // Set default DataIndex — writes to BaseDataObjectStorage.defaultDataIndex
        await dataObject.write.setDefaultDataIndexImplementation([dataIndex.address]);

        // Compute expected ERC-7201 slot
        const expectedSlot = computeERC7201Slot("nexera-foundation.erc7208-core.storage.BaseDataObject");

        // defaultDataIndex is the first field in the struct, so it's at the base slot
        const storedValue = await publicClient.getStorageAt({
            address: proxy.address,
            slot: expectedSlot,
        });

        // Storage contains the address left-padded to 32 bytes
        const storedAddress = getAddress(`0x${storedValue!.slice(26)}`);
        assert.equal(
            storedAddress,
            getAddress(dataIndex.address),
            `defaultDataIndex should be stored at ERC-7201 slot for "nexera-foundation.erc7208-core.storage.BaseDataObject"`,
        );
    });

    it("CallbackProcessorDataObjectUpgradeable uses correct ERC-7201 slot for callback data", async () => {
        // Deploy upgradeable callback DataObject behind a proxy
        const { proxy } = await ignition.deploy(SampleCallbackDataObjectUpgradeableModule);
        const dataObject = await viem.getContractAt("SampleCallbackDataObjectUpgradeable", proxy.address);
        const handler = (await ignition.deploy(MockCallbackHandlerModule)).handler;

        // Wire up: allocate DP, set DataIndex, approve deployer as DataManager
        const dp = (await registry.simulate.allocate([deployer.account.address])).result;
        await registry.write.allocate([deployer.account.address]);
        await dataObject.write.setDataIndexImplementation([dp, dataIndex.address]);
        await dataIndex.write.allowDataManager([dp, deployer.account.address, true]);

        // Register a callback handler via DataIndex.write → _dispatchWrite
        const registerData = encodeAbiParameters(
            parseAbiParameters("address, uint256, bytes"),
            [handler.address, ALL_OPERATIONS, "0x"],
        );
        await dataIndex.write.write([
            dataObject.address,
            dp,
            REGISTER_CALLBACK_SELECTOR,
            registerData,
        ]);

        // Compute expected ERC-7201 base slot for CallbackProcessorDataObject
        const baseSlot = computeERC7201Slot("nexera-foundation.erc7208-core.storage.CallbackProcessorDataObject");

        // Storage layout:
        //   CallbackProcessorDataObjectStorage { mapping(DataPoint => CallbackProcessorDpData) callbackProcessorData }
        //   callbackProcessorData is at slot baseSlot + 0 (first/only field)
        //   For mapping(DataPoint => CallbackProcessorDpData), the data for key `dp` is at:
        //     keccak256(abi.encode(dp, baseSlot))
        //   CallbackProcessorDpData.handlers is an EnumerableSet.AddressSet at offset 0
        //   EnumerableSet.AddressSet wraps Set which has: bytes32[] _values (slot 0), mapping _positions (slot 1)
        //   The length of _values array is stored at the Set's base slot

        const dpDataSlot = keccak256(
            encodeAbiParameters(parseAbiParameters("bytes32, uint256"), [dp, BigInt(baseSlot)]),
        );

        // dpDataSlot points to CallbackProcessorDpData, whose first field is the EnumerableSet
        // EnumerableSet → Set → bytes32[] _values at offset 0
        // Array length is stored at the array's slot itself
        const arrayLengthSlot = dpDataSlot;

        const storedLength = await publicClient.getStorageAt({
            address: proxy.address,
            slot: arrayLengthSlot,
        });

        assert.equal(
            BigInt(storedLength!),
            1n,
            `Handler set length should be 1 at the ERC-7201 derived slot for "nexera-foundation.erc7208-core.storage.CallbackProcessorDataObject"`,
        );
    });
});
