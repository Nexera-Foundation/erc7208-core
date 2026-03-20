import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("MockCallbackHandler", (m) => {
    const handler = m.contract("MockCallbackHandler");
    return { handler };
});
