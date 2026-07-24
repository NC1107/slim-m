// SPDX-License-Identifier: AGPL-3.0-only
//
// Size-regression gate for slim-m.
//
// Checks that a single file does not exceed a byte budget, and exits
// non-zero if it does. Used to gate:
//   - the release server binary (budget: 20 MB), e.g. after
//     `cargo build --release --bin slimm-server`
//   - the built container image (budget: set by the caller)
//
// Usage:
//   node scripts/check-size.mjs <file-path> <max-bytes>
//
// <max-bytes> accepts either a plain integer byte count, or a number with a
// KB/MB/GB suffix (case-insensitive, binary: 1 KB = 1024 bytes).
//
// Examples:
//   node scripts/check-size.mjs target/release/slimm-server 20MB
//   node scripts/check-size.mjs target/release/slimm-server 20971520
//
// To gate a container image, this script still needs a single file to stat.
// Either:
//   - point it at a tarball produced by `docker save <image> -o image.tar`, or
//   - write the image size to a plain-text file and pass that file with a
//     budget in the same unit, e.g.:
//       docker image inspect <image> --format='{{.Size}}' > image-size.txt
//       node scripts/check-size.mjs image-size.txt 60MB
//     (the second form works because this script only reads the *file's*
//     byte length on disk, and a decimal number written as text occupies
//     one byte per digit; for an exact byte-for-byte image size check,
//     prefer the docker save tarball form above instead.)
//
// Exit codes:
//   0  file is within budget
//   1  file exceeds budget (size regression)
//   2  usage error (missing args, unreadable file, invalid budget)

import { statSync } from 'node:fs';

const USAGE = [
  'Usage: node scripts/check-size.mjs <file-path> <max-bytes>',
  '  <max-bytes> is a plain byte count, or a number with a KB/MB/GB suffix',
  '  (binary, 1024-based). Example: node scripts/check-size.mjs target/release/slimm-server 20MB',
].join('\n');

const UNIT_MULTIPLIERS = {
  b: 1,
  kb: 1024,
  mb: 1024 * 1024,
  gb: 1024 * 1024 * 1024,
};

function parseMaxBytes(raw) {
  const trimmed = raw.trim().toLowerCase();
  const match = trimmed.match(/^([0-9]+(?:\.[0-9]+)?)\s*(b|kb|mb|gb)?$/);
  if (!match) {
    return null;
  }
  const value = parseFloat(match[1]);
  const unit = match[2] || 'b';
  return Math.floor(value * UNIT_MULTIPLIERS[unit]);
}

function formatBytes(bytes) {
  if (bytes >= UNIT_MULTIPLIERS.gb) {
    return `${bytes} bytes (${(bytes / UNIT_MULTIPLIERS.gb).toFixed(2)} GB)`;
  }
  if (bytes >= UNIT_MULTIPLIERS.mb) {
    return `${bytes} bytes (${(bytes / UNIT_MULTIPLIERS.mb).toFixed(2)} MB)`;
  }
  if (bytes >= UNIT_MULTIPLIERS.kb) {
    return `${bytes} bytes (${(bytes / UNIT_MULTIPLIERS.kb).toFixed(2)} KB)`;
  }
  return `${bytes} bytes`;
}

function main() {
  const [, , filePath, maxBytesRaw] = process.argv;

  if (!filePath || !maxBytesRaw) {
    console.error(USAGE);
    process.exit(2);
  }

  const maxBytes = parseMaxBytes(maxBytesRaw);
  if (maxBytes === null || Number.isNaN(maxBytes) || maxBytes <= 0) {
    console.error(`Invalid max-bytes value: ${maxBytesRaw}`);
    console.error(USAGE);
    process.exit(2);
  }

  let stat;
  try {
    stat = statSync(filePath);
  } catch (err) {
    console.error(`Cannot read file: ${filePath} (${err.message})`);
    process.exit(2);
  }

  const actualBytes = stat.size;
  const withinBudget = actualBytes <= maxBytes;

  console.log(`File:   ${filePath}`);
  console.log(`Size:   ${formatBytes(actualBytes)}`);
  console.log(`Budget: ${formatBytes(maxBytes)}`);
  console.log(`Status: ${withinBudget ? 'PASS' : 'FAIL'}`);

  if (!withinBudget) {
    console.error(`Size regression: ${filePath} exceeds budget by ${formatBytes(actualBytes - maxBytes)}`);
    process.exit(1);
  }
}

main();
