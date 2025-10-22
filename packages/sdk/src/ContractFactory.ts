import { Contract, Interface, InterfaceAbi } from 'ethers';

/**
 * Generic Contract Factory
 * Factory class for creating ethers Contract instances
 */
export class ContractFactory {
  /**
   * The contract ABI
   */
  readonly abi: InterfaceAbi;

  /**
   * Creates a new ContractFactory instance
   * @param abi - The contract ABI
   */
  constructor(abi: InterfaceAbi) {
    this.abi = abi;
  }

  /**
   * Connect to an existing contract
   * @param address - The contract address
   * @returns Contract instance
   */
  connect(address: string): Contract {
    return new Contract(address, this.abi);
  }

  /**
   * Create a contract interface for encoding/decoding
   * @returns Interface instance
   */
  createInterface(): Interface {
    return new Interface(this.abi);
  }

  /**
   * Get the contract ABI as a JSON string
   * @returns JSON string of the ABI
   */
  getAbiJson(): string {
    return JSON.stringify(this.abi, null, 2);
  }
}

