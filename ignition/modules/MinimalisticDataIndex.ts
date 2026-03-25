import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("MinimalisticDataIndex", (m) => {
    const dataIndex = m.contract("MinimalisticDataIndex");
    return { dataIndex };
});
