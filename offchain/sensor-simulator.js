import { randomInt } from "node:crypto";

const MODES = new Set(["normal", "violation", "random"]);

export function celsiusToTenths(value) {
  const celsius = Number(value);
  if (!Number.isFinite(celsius)) {
    throw new Error("Temperature must be a number in degrees Celsius.");
  }

  const tenths = Math.round(celsius * 10);
  if (tenths < -32768 || tenths > 32767) {
    throw new Error("Temperature does not fit the contract int16 representation.");
  }
  return tenths;
}

export function simulatedTemperature(mode = "normal") {
  if (!MODES.has(mode)) {
    throw new Error(`Unknown mode '${mode}'. Use normal, violation, or random.`);
  }

  if (mode === "normal") return randomInt(35, 51);
  if (mode === "violation") return randomInt(70, 101);
  return randomInt(-10, 101);
}

export function generateReading({
  batchId,
  nonce,
  temperatureCelsius,
  mode = "normal",
  measuredAt = Math.floor(Date.now() / 1000)
}) {
  const numericBatchId = Number(batchId);
  const numericNonce = Number(nonce);
  const numericMeasuredAt = Number(measuredAt);

  if (!Number.isSafeInteger(numericBatchId) || numericBatchId <= 0) {
    throw new Error("Batch ID must be a positive integer.");
  }
  if (!Number.isSafeInteger(numericNonce) || numericNonce < 0) {
    throw new Error("Nonce must be a non-negative integer.");
  }
  if (!Number.isSafeInteger(numericMeasuredAt) || numericMeasuredAt <= 0) {
    throw new Error("Measured-at timestamp must be a positive Unix timestamp.");
  }

  return {
    batchId: numericBatchId,
    temperatureTenths:
      temperatureCelsius === undefined
        ? simulatedTemperature(mode)
        : celsiusToTenths(temperatureCelsius),
    measuredAt: numericMeasuredAt,
    nonce: numericNonce
  };
}
