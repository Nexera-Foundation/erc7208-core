#!/usr/bin/env node
/**
 * Computes an ERC-7201 storage slot from a namespace string.
 *
 * Formula: keccak256(abi.encode(uint256(keccak256(namespace)) - 1)) & ~bytes32(uint256(0xff))
 *
 * Usage:
 *   node scripts/erc7201-slot.mjs <namespace>
 *
 * Example:
 *   node scripts/erc7201-slot.mjs "nexera-foundation.erc7208-core.storage.SampleDataObject"
 */

import { keccak256, toBytes, toHex, pad } from "viem";

const namespace = process.argv[2];
if (!namespace) {
  console.error("Usage: node scripts/erc7201-slot.mjs <namespace>");
  process.exit(1);
}

const hash = keccak256(toBytes(namespace));
const adjusted = pad(toHex(BigInt(hash) - 1n), { size: 32 });
const slot = keccak256(toBytes(adjusted));
const masked = BigInt(slot) & ~BigInt(0xff);
const result = toHex(masked, { size: 32 });

console.log(result);
