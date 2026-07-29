import { Contract, JsonRpcProvider, Wallet, getBytes } from "ethers";
import { loadArtifact } from "./config.js";

const BATCH_STATUSES = [
  "None",
  "Created",
  "InTransit",
  "Delivered",
  "NonCompliant",
  "Recalled"
];

function errorMessage(error) {
  return error.shortMessage || error.reason || error.message || String(error);
}

export class OracleService {
  constructor(config, storage) {
    this.storage = storage;
    this.provider = new JsonRpcProvider(config.rpcUrl);
    this.sensorWallet = new Wallet(config.sensorPrivateKey);
    this.relayerWallet = new Wallet(config.relayerPrivateKey, this.provider);

    const complianceAbi = loadArtifact("ColdChainCompliance").abi;
    const batchAbi = loadArtifact("BatchRegistry").abi;

    this.compliance = new Contract(
      config.complianceAddress,
      complianceAbi,
      this.relayerWallet
    );
    this.batchRegistry = new Contract(
      config.batchRegistryAddress,
      batchAbi,
      this.provider
    );
  }

  get sensorAddress() {
    return this.sensorWallet.address;
  }

  nextNonce() {
    return this.storage.nextNonce(this.sensorAddress);
  }

  async submit(reading) {
    const recordId = this.storage.insertGenerated(reading, this.sensorAddress);

    try {
      await this.#validate(reading);

      const digest = await this.compliance.getReadingDigest(
        reading.batchId,
        reading.temperatureTenths,
        reading.measuredAt,
        reading.nonce
      );
      const signature = await this.sensorWallet.signMessage(getBytes(digest));
      this.storage.markSigned(recordId, digest, signature);

      const transaction = await this.compliance.submitSignedReading(
        reading.batchId,
        reading.temperatureTenths,
        reading.measuredAt,
        reading.nonce,
        signature
      );
      this.storage.markSubmitted(recordId, transaction.hash);

      const receipt = await transaction.wait();
      const latest = await this.compliance.getLatestReading(reading.batchId);
      const batch = await this.batchRegistry.getBatch(reading.batchId);
      const batchStatus = BATCH_STATUSES[Number(batch.status)] ?? `Unknown(${batch.status})`;

      this.storage.markConfirmed(recordId, {
        blockNumber: Number(receipt.blockNumber),
        violation: latest.violation,
        batchStatus
      });

      return {
        recordId,
        digest,
        signature,
        transactionHash: transaction.hash,
        blockNumber: Number(receipt.blockNumber),
        violation: latest.violation,
        batchStatus,
        currentCustodian: batch.currentCustodian
      };
    } catch (error) {
      const message = errorMessage(error);
      this.storage.markFailed(recordId, message);
      error.recordId = recordId;
      throw error;
    }
  }

  async #validate(reading) {
    const now = Math.floor(Date.now() / 1000);
    const maximumAge = Number(await this.compliance.maximumReadingAge());

    if (reading.measuredAt > now) {
      throw new Error("Reading timestamp is in the future.");
    }
    if (now - reading.measuredAt > maximumAge) {
      throw new Error(`Reading is older than the contract limit of ${maximumAge} seconds.`);
    }
  }
}
