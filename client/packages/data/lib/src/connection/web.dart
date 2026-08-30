// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The browser backend: sqlite3 compiled to WebAssembly, hosted in a worker
/// so the query loop never blocks the frame.
///
/// Both asset names are fixed by what `web/` serves; see `web/README.md` in
/// the app package for where those two files come from and how to refresh
/// them. They are served from the app's own origin, never a CDN, so a
/// self-hosted deployment stays self-contained.
library;

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart';

/// The IndexedDB/OPFS database name. Changing it orphans every existing
/// browser's cache rather than migrating it.
const slimmDatabaseName = 'slimm';

/// Opens the browser-backed database, letting drift pick the most durable
/// storage the browser offers: OPFS first, then IndexedDB, then memory.
///
/// The cache is disposable by design (see `SlimmDatabase`'s migration notes),
/// so an unlucky browser degrades to re-syncing rather than to losing
/// anything the server does not already hold.
Future<QueryExecutor> openSlimmDatabase() async {
  final result = await WasmDatabase.open(
    databaseName: slimmDatabaseName,
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );
  if (result.chosenImplementation == WasmStorageImplementation.inMemory) {
    // Said out loud because the symptom otherwise reads as a sync bug: every
    // reload starts from an empty channel list and refetches everything.
    debugPrint(
      'slim-m: no durable storage in this browser '
      '(${result.missingFeatures.join(', ')}); the local cache is memory-only',
    );
  }
  return result.resolvedExecutor;
}
