// SPDX-License-Identifier: Apache-2.0
/// Gates schema/openapi.yaml against the routes SlimmApi actually calls.
///
/// The mirror image of crates/slimm-server/tests/openapi_contract.rs on this
/// side of the wire. That test reads the router's real source rather than
/// trusting a hand-maintained list, because a list that only stays accurate
/// if someone remembers to update it always rots; this file does the same
/// for the client, which is exactly how it drifted to documenting roughly
/// twice as many routes as it called in the first place.
///
/// Both sides of the comparison are extracted from source text, not from a
/// generic parser:
///
/// - The schema side is a line-based reader tuned to this file's consistent
///   2-space indent, the same approach and the same trade-off the Rust
///   extractor makes (see its module doc for why: a full YAML parser would
///   also have to resolve `$ref`, which the OpenAPI structure itself does not
///   need for a route-surface comparison).
/// - The client side scans every `.dart` file under lib/src for
///   `_send('METHOD', '/path...')` call sites. It cannot see calls that build
///   their path from anything other than a literal (there are none today),
///   which is why it self-checks: the number of call sites that look
///   literal-led must equal the number that fully parse, so a call shape this
///   scanner cannot handle fails the test instead of silently disappearing
///   from the comparison.
library;

import 'dart:io';

import 'package:test/test.dart';

/// Routes reachable through something other than `_send`, so their absence
/// from the scanned call set is not drift. Each key is `METHOD /normalized/path`.
const Map<String, String> _allowlist = {
  'GET /healthz': 'read with a raw http.get in SlimmApi.health, not _send: a '
      'failed liveness probe must never be treated as an expired session and '
      'trigger a token refresh',
  'GET /ws': 'an HTTP upgrade opened by web_socket_channel in events.dart, '
      'not a request/response call _send could make',
  'GET /attachments/{}': 'reads raw bytes through SlimmApi._fetchBytes, not '
      '_send: a response that is never JSON needs no JSON decode attempt to '
      'fail on',
  'GET /users/{}/avatar': 'reads raw bytes through SlimmApi._fetchBytes, the '
      'same as GET /attachments/{}',
};

const _httpMethods = {
  'get',
  'post',
  'put',
  'patch',
  'delete',
  'head',
  'options',
  'trace',
};

void main() {
  final repoRoot = _findRepoRoot(Directory.current);
  final schemaFile = File('${repoRoot.path}/schema/openapi.yaml');
  final clientSrcDir =
      Directory('${repoRoot.path}/client/packages/api/lib/src');

  test('the schema and client route extractors both find something', () {
    // A gate that can silently see zero routes on either side would pass
    // forever without checking anything; fail loudly instead.
    expect(_extractSchemaRoutes(schemaFile), isNotEmpty);
    expect(_extractClientRouteKeys(clientSrcDir), isNotEmpty);
  });

  test('the allowlist only names routes the schema actually documents', () {
    // Guards against a stale entry surviving a route rename or removal, which
    // would otherwise quietly widen the gate for nothing.
    final schemaKeys =
        _extractSchemaRoutes(schemaFile).map((r) => r.key).toSet();
    for (final key in _allowlist.keys) {
      expect(
        schemaKeys,
        contains(key),
        reason: '$key is allowlisted but not documented in schema/openapi.yaml',
      );
    }
  });

  test(
      'every documented route has a matching SlimmApi call, or a reasoned '
      'allowlist entry', () {
    final schemaRoutes = _extractSchemaRoutes(schemaFile);
    final clientKeys = _extractClientRouteKeys(clientSrcDir);

    final missing = <String>[];
    for (final route in schemaRoutes) {
      if (clientKeys.contains(route.key)) continue;
      if (_allowlist.containsKey(route.key)) continue;
      missing.add(
        '${route.key} (schema/openapi.yaml:${route.line}) has no matching '
        '_send call anywhere under client/packages/api/lib/src, and no '
        'allowlist entry',
      );
    }
    missing.sort();

    expect(
      missing,
      isEmpty,
      reason: '\nclient/packages/api has drifted from schema/openapi.yaml:\n\n'
          '${missing.join('\n')}\n',
    );
  });
}

// --- Locating the repo ---

/// Walks upward from [start] looking for schema/openapi.yaml, so the test
/// does not depend on whether it was invoked from the repo root, from
/// client/, or from client/packages/api (all three are realistic: `dart
/// test`, `flutter test`, and CI each tend to run from a different one).
Directory _findRepoRoot(Directory start) {
  var dir = start.absolute;
  for (var i = 0; i < 10; i++) {
    if (File('${dir.path}/schema/openapi.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail(
    'could not find schema/openapi.yaml walking up from ${start.path}; is '
    'this test running from somewhere inside the slim-m repo?',
  );
}

// --- Schema-side extraction ---

class _SchemaRoute {
  const _SchemaRoute(this.method, this.path, this.line);

  final String method;
  final String path;
  final int line;

  String get key => '$method $path';
}

/// Extracts every `(method, path)` documented under `paths:` in
/// schema/openapi.yaml. A path key sits at exactly two spaces of indent
/// (`  /channels:`) and an HTTP-method key for it sits at exactly four
/// (`    get:`), sibling to things like `parameters:` that are skipped
/// because they are not one of the known verbs.
List<_SchemaRoute> _extractSchemaRoutes(File schemaFile) {
  final lines = schemaFile.readAsLinesSync();
  final routes = <_SchemaRoute>[];
  var inPaths = false;
  String? currentPath;

  for (var i = 0; i < lines.length; i++) {
    final rawLine = lines[i];
    final lineNo = i + 1;

    if (rawLine == 'paths:') {
      inPaths = true;
      continue;
    }
    if (!inPaths) continue;
    if (rawLine.trim().isEmpty) continue;
    // A line back at column 0 (`components:`) ends the `paths:` block.
    if (!rawLine.startsWith(' ')) break;

    final indent = rawLine.length - rawLine.trimLeft().length;
    final trimmed = rawLine.trim();

    if (indent == 2 && trimmed.startsWith('/') && trimmed.endsWith(':')) {
      currentPath = trimmed.substring(0, trimmed.length - 1);
      continue;
    }

    if (indent == 4 && trimmed.endsWith(':')) {
      final key = trimmed.substring(0, trimmed.length - 1);
      if (key.isNotEmpty && !key.contains(' ') && _httpMethods.contains(key)) {
        final path = currentPath;
        if (path == null) {
          fail(
            'schema/openapi.yaml:$lineNo: found method `$key:` with no '
            'enclosing path key above it',
          );
        }
        routes.add(_SchemaRoute(key.toUpperCase(), _normalize(path), lineNo));
      }
    }
  }

  return routes;
}

// --- Client-side extraction ---

/// Matches a call site whose first argument is a string literal, e.g.
/// `_send('GET', ...`. Deliberately narrower than matching `_send(` alone: it
/// must exclude the method's own declaration (`Future<Object?> _send(` is
/// followed by a type, not a quote) and its recursive retry call (followed by
/// the bare `method` identifier, not a quote), neither of which is a route.
final RegExp _literalLedCall = RegExp(r"_send\(\s*'");

/// The same call site, fully parsed into its method and path literals.
final RegExp _fullCall = RegExp(r"_send\(\s*'([A-Z]+)'\s*,\s*'([^']*)'");

/// Scans every `.dart` file directly under [srcDir] for `_send(...)` call
/// sites and returns the normalized `METHOD /path` key for each.
///
/// Self-checks per file: every call site this function's own literal-led
/// detector *finds* must also be fully *parsed*, or it fails loudly rather
/// than quietly returning a partial (and therefore falsely narrow) route set.
Set<String> _extractClientRouteKeys(Directory srcDir) {
  final keys = <String>{};

  final files = srcDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
  expect(
    files,
    isNotEmpty,
    reason: 'found no .dart files under ${srcDir.path}; route discovery '
        'itself is broken, not the client having no source',
  );

  for (final file in files) {
    final text = file.readAsStringSync();
    final literalLedCount = _literalLedCall.allMatches(text).length;
    final parsed = _fullCall.allMatches(text).toList();

    expect(
      parsed.length,
      literalLedCount,
      reason: '${file.path}: found $literalLedCount call site(s) shaped like '
          "_send('...', but only parsed ${parsed.length} into a method and "
          'a path literal; fix _fullCall in schema_coverage_test.dart before '
          'trusting this gate',
    );

    for (final match in parsed) {
      final method = match.group(1)!;
      final path = match.group(2)!;
      keys.add('$method ${_placeholderInterpolations(path)}');
    }
  }

  return keys;
}

/// Replaces a Dart string-interpolation path segment (`$channelId`,
/// `${kind.wire}`) with the same `{}` placeholder [_normalize] turns a
/// schema `{channelId}` segment into, so the two sides compare equal despite
/// spelling "one path parameter here" completely differently.
String _placeholderInterpolations(String path) => path
    .split('/')
    .map((segment) => segment.contains('\$') ? '{}' : segment)
    .join('/');

// --- Shared normalization ---

/// Turns a schema `{channelId}`-style segment into the same `{}` placeholder
/// [_placeholderInterpolations] produces for the client side. Every other
/// segment, and the number and order of segments, is compared literally, so a
/// genuinely different path still fails.
String _normalize(String path) => path
    .split('/')
    .map((segment) =>
        segment.startsWith('{') && segment.endsWith('}') && segment.length >= 2
            ? '{}'
            : segment)
    .join('/');
