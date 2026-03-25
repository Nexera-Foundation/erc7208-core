import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("SampleDataObjectUpgradeable", (m) => {
    const deployer = m.getAccount(0);
    const impl = m.contract("SampleDataObjectUpgradeable");
    const initData = m.encodeFunctionCall(impl, "initialize", []);
    const proxy = m.contract("TestTransparentProxy", [impl, deployer, initData], { id: "proxy" });
    return { proxy, impl };
});
