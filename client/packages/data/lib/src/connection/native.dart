// SPDX-License-Identifier: Apache-2.0
/// The native backend: sqlite3 through `dart:ffi`, in one file under the
/// application support directory.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The file name is part of the contract with anyone debugging a user's
/// install, so it is fixed here rather than derived.
const slimmDatabaseFileName = 'slimm.sqlite';

/// Opens the on-disk database backing the local cache.
///
/// Runs sqlite3 on a background isolate: every query on the platform that
/// ships to users therefore stays off the frame-building isolate.
Future<QueryExecutor> openSlimmDatabase() async {
  final directory = await getApplicationSupportDirectory();
  return NativeDatabase.createInBackground(
    File(p.join(directory.path, slimmDatabaseFileName)),
  );
}
