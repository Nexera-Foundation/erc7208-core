import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("SampleCallbackDataObject", (m) => {
    const dataObject = m.contract("SampleCallbackDataObject");
    return { dataObject };
});
