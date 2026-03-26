# Accepted Risks & Won't-Fix Decisions

Reference for future audits/reviews. These items have been evaluated and
intentionally left as-is. If a future reviewer flags any of these, point
them here rather than re-litigating.

## 1. Gas griefing via unbounded handler set

No built-in cap on handlers per DataPoint. A malicious/careless DataManager
could register enough handlers to make `_processCallbacks` exceed block gas limit.

**Why not fixing:** NatSpec warns about this. Inheriting contracts can override
`_dispatchWrite` to enforce a cap. Adding a hard cap to the base implementation
would reduce flexibility for legitimate use cases.

## 2. NatSpec `@param` tags missing on commented-out parameters

Extension point functions use commented-out params (e.g. `/*dp*/`) for unused args.

**Why not fixing:** Adding `@param` for commented-out parameter names causes compiler
warnings about documenting non-existent parameters. Bare `param` (without `@`) is
used intentionally to describe the parameter purpose without triggering warnings.

## 3. calldata/memory mismatch documentation for `handleDataObjectCallback`

Handler context is loaded from storage into memory before the external call,
while the interface declares `calldata` params. Solidity handles the conversion
automatically at the ABI boundary.

**Why not fixing:** Standard Solidity behavior, extra comment would be noise.

## 4. No single-handler query or `isRegistered` check operations

`ICallbackProcessorOperations` does not expose per-handler queries (get single
handler properties, check if registered).

**Why not fixing:** Keeping the operations interface minimal reduces dispatch
branches and lowers the risk of selector collisions. Callers can use
`getCallbackHandlers` to inspect the full set.

## 5. `_registerCallback` / `_unregisterCallback` / `_updateCallbackMask` are private

Subclasses cannot override registration logic directly; they must intercept
at the `_dispatchWrite` level.

**Why not fixing:** This is a reference implementation, not a framework. Projects
needing deeper customization can create their own CallbackProcessor.

## 6. Handler execution order is not guaranteed

`EnumerableSet` does not preserve insertion order. Handler invocation sequence
may change after additions/removals.

**Why not fixing:** Documented in contract-level NatSpec. Guaranteeing order would
require a different data structure with higher gas costs. Handlers should be
designed to be order-independent.
