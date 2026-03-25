import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("SampleDataObject", (m) => {
    const dataObject = m.contract("SampleDataObject");
    return { dataObject };
});
