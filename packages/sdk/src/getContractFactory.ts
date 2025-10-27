import { ContractFactory } from './ContractFactory';

/**
 * Gets a contract factory for the specified contract name
 * @param contractName - The name of the contract (e.g., "DataPointRegistry")
 * @returns ContractFactory instance for the specified contract
 * @throws Error if the contract artifact is not found
 */
export function getContractFactory(contractName: string): ContractFactory {
	try {
		// Dynamically import the artifact JSON file
		const artifact = require(`./artifacts/${contractName}.json`);

		if (!artifact || !artifact.abi) {
			throw new Error(`Contract artifact for "${contractName}" does not contain an ABI`);
		}

		return new ContractFactory(artifact.abi);
	} catch (error) {
		if (error instanceof Error) {
			throw new Error(
				`Failed to load contract "${contractName}": ${error.message}. ` +
					`Make sure the contract artifact exists in the artifacts folder.`
			);
		}
		throw error;
	}
}

/**
 * Gets the contract ABI for the specified contract name
 * @param contractName - The name of the contract (e.g., "DataPointRegistry")
 * @returns The contract ABI
 * @throws Error if the contract artifact is not found
 */
export function getContractAbi(contractName: string): any {
	try {
		const artifact = require(`./artifacts/${contractName}.json`);

		if (!artifact || !artifact.abi) {
			throw new Error(`Contract artifact for "${contractName}" does not contain an ABI`);
		}

		return artifact.abi;
	} catch (error) {
		if (error instanceof Error) {
			throw new Error(`Failed to load contract ABI for "${contractName}": ${error.message}`);
		}
		throw error;
	}
}
