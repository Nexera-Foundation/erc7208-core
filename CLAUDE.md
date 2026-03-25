# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ERC-7208 reference implementation by Nexera Foundation. Provides interfaces and base contracts for the ERC-7208 Data Object pattern — a standard for managing on-chain data through DataPoints (unique 32-byte identifiers), DataObjects (storage), and DataIndex (access control/routing).

## Build & Test Commands

```bash
yarn build          # Compile contracts (hardhat compile)
yarn test           # Run all tests
yarn test:solidity  # Run Solidity tests only
yarn test:nodejs    # Run Node.js tests only
yarn lint           # Format code with prettier
yarn clean          # Clean hardhat artifacts
```

Hardhat 3.0 with `hardhat-toolbox-viem` plugin. Solidity 0.8.30. Tests use Node.js native test runner with Hardhat Viem integration and `hardhat-viem-assertions`.

### Test Organization

- **Solidity tests** (`contracts/tests/*.t.sol`) — Foundry/Forge unit tests. Test individual contract functions and edge cases in isolation.
- **TypeScript tests** (`test/*.ts`) — Integration/end-to-end/workflow tests. Test multi-contract interactions, deployment flows, access control scenarios, and full protocol workflows using Hardhat Viem.

## Architecture

### Core Protocol Components

**DataPoint** — 32-byte identifier encoding type prefix (`0x4450`), version, chain ID, and registry address. Defined/encoded in `contracts/utils/DataPoints.sol`.

**DataPointRegistry** (`contracts/DataPointRegistry.sol`) — Allocates DataPoints and manages ownership + admin roles. Central authority for access control.

**DataObject** — Stores data associated with DataPoints. Base implementations:
- `contracts/utils/BaseDataObject.sol` — Standard version with dispatch pattern (`_dispatchRead`/`_dispatchWrite` for extensible operation handling)
- `contracts/utils/BaseDataObjectUpgradeable.sol` — Upgradeable version using ERC7201 storage pattern

**DataIndex** (`contracts/MinimalisticDataIndex.sol`) — Access control and routing layer. Manages DataManager approvals per DataPoint. Only DataPoint admins can grant/revoke access.

### Callback System

Mixin contracts that add callback handler support to DataObjects:
- `contracts/utils/CallbackProcessorDataObject.sol` — Standard version
- `contracts/utils/CallbackProcessorDataObjectUpgradeable.sol` — Upgradeable version

Handlers are filtered by task bitmask. Extension points: `_beforeProcessCallbacks`, `_afterProcessCallbacks`, `_onCallbackHandlerSuccess`, `_onCallbackHandlerFailure`.

### Key Interfaces (contracts/interfaces/)

- `IDataObject` / `IBaseDataObject` — read/write operations and DataIndex management
- `IDataIndex` — access control routing
- `IDataPointRegistry` — registry operations
- `IDataObjectCallbackHandler` — callback handler interface
- `ICallbackProcessorOperations` — callback registration

**Operations interfaces** (e.g. `ICallbackProcessorOperations`) are **not externally implemented interfaces** — they serve as selector sources for the dispatch pattern. DataObjects use the function selectors defined in these interfaces to route operations inside `_dispatchRead`/`_dispatchWrite`, but they never expose those functions as direct external calls. Therefore, Operations interfaces should **not** be advertised via ERC-165 `supportsInterface`.

### Patterns

- **Dispatch pattern**: DataObjects use `_dispatchRead`/`_dispatchWrite` virtual functions for extensible operation routing
- **Dual variants**: Most base contracts have both standard and upgradeable (ERC7201 storage) versions — changes must be kept in sync
- **OpenZeppelin v5**: AccessControl, ReentrancyGuardTransient, EnumerableSet, ERC165

## Project Structure

- `contracts/` — Core contracts, interfaces, utilities, and examples
- `contracts/examples/` — Sample implementations including a "Race to the Target" game
- `test/` — Node.js/TypeScript tests using Hardhat Viem
- `ignition/` — Hardhat Ignition deployment modules

## Dependencies

- OpenZeppelin Contracts & Contracts-Upgradeable v5.6.1
- Hardhat 3.0 with Viem toolbox
- Published as `@nexera-foundation/erc7208-core` to GitHub npm registry
