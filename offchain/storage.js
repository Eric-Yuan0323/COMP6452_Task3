import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";

export class ReadingStorage {
  constructor(databasePath) {
    mkdirSync(dirname(databasePath), { recursive: true });
    this.database = new DatabaseSync(databasePath);
    this.database.exec("PRAGMA journal_mode = WAL;");
    this.database.exec(`
      CREATE TABLE IF NOT EXISTS sensor_readings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_id INTEGER NOT NULL,
        temperature_tenths INTEGER NOT NULL,
        measured_at INTEGER NOT NULL,
        nonce INTEGER NOT NULL,
        sensor_address TEXT NOT NULL,
        digest TEXT,
        signature TEXT,
        transaction_hash TEXT,
        block_number INTEGER,
        violation INTEGER,
        batch_status TEXT,
        submission_status TEXT NOT NULL,
        error_message TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(sensor_address, nonce)
      );
    `);
  }

  nextNonce(sensorAddress) {
    const row = this.database
      .prepare(`
        SELECT COALESCE(MAX(nonce), -1) + 1 AS next_nonce
        FROM sensor_readings
        WHERE lower(sensor_address) = lower(?)
      `)
      .get(sensorAddress);
    return Number(row.next_nonce);
  }

  insertGenerated(reading, sensorAddress) {
    const result = this.database
      .prepare(`
        INSERT INTO sensor_readings (
          batch_id, temperature_tenths, measured_at, nonce,
          sensor_address, submission_status
        ) VALUES (?, ?, ?, ?, ?, 'generated')
      `)
      .run(
        reading.batchId,
        reading.temperatureTenths,
        reading.measuredAt,
        reading.nonce,
        sensorAddress
      );
    return Number(result.lastInsertRowid);
  }

  markSigned(id, digest, signature) {
    this.#update(
      `digest = ?, signature = ?, submission_status = 'signed'`,
      [digest, signature, id]
    );
  }

  markSubmitted(id, transactionHash) {
    this.#update(
      `transaction_hash = ?, submission_status = 'submitted'`,
      [transactionHash, id]
    );
  }

  markConfirmed(id, { blockNumber, violation, batchStatus }) {
    this.#update(
      `block_number = ?, violation = ?, batch_status = ?, submission_status = 'confirmed'`,
      [blockNumber, violation ? 1 : 0, batchStatus, id]
    );
  }

  markFailed(id, errorMessage) {
    this.#update(
      `error_message = ?, submission_status = 'failed'`,
      [errorMessage, id]
    );
  }

  getReading(id) {
    return this.database.prepare("SELECT * FROM sensor_readings WHERE id = ?").get(id);
  }

  close() {
    this.database.close();
  }

  #update(assignments, values) {
    this.database
      .prepare(`UPDATE sensor_readings SET ${assignments}, updated_at = CURRENT_TIMESTAMP WHERE id = ?`)
      .run(...values);
  }
}
