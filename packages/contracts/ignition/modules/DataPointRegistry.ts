import {buildModule} from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("DataPointRegistry", (m) => {
    const registry = m.contract("DataPointRegistry");
    return {registry};
});
