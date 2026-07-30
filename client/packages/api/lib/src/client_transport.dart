// SPDX-License-Identifier: Apache-2.0
part of 'client.dart';

/// The only code in this package that speaks HTTP.
///
/// Every typed method in every other part of [SlimmApi] is a wrapper over
/// [SlimmApi._send] or [SlimmApi._fetchBytes], which is why the one-shot
/// refresh-and-replay, the status-to-exception mapping, and turning a path
/// built from a wire-supplied value into a safe request [Uri] are all
/// written once, here, rather than per endpoint.
extension SlimmApiTransport on SlimmApi {
  Future<Object?> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    List<int>? bytes,
    Map<String, String>? query,
    bool authenticated = true,
    bool expectNoContent = false,
    bool isRetry = false,
  }) async {
    final uri = _requestUri(path, query);
    final request = http.Request(method, uri);
    if (bytes != null) {
      // An upload (an attachment or an avatar): the request body is the raw
      // bytes, never JSON, though the response below still is.
      request.headers['content-type'] = 'application/octet-stream';
      request.bodyBytes = bytes;
    } else if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (authenticated) {
      final token = session.tokens?.accessToken;
      if (token == null) {
        throw const UnauthorizedException('not signed in');
      }
      request.headers['authorization'] = 'Bearer $token';
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } catch (e) {
      throw TransportException('$method $path failed: $e');
    }

    // One automatic rotation, then replay. Only for authenticated calls, and
    // never twice for the same request.
    if (response.statusCode == 401 &&
        authenticated &&
        !isRetry &&
        session.tokens != null) {
      await refresh();
      return _send(
        method,
        path,
        body: body,
        bytes: bytes,
        query: query,
        authenticated: authenticated,
        expectNoContent: expectNoContent,
        isRetry: true,
      );
    }

    if (response.statusCode == 204 ||
        (expectNoContent && response.statusCode < 300)) {
      return null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      try {
        return jsonDecode(response.body) as Object;
      } catch (e) {
        throw TransportException(
          'could not decode the reply to $method $path: $e',
        );
      }
    }
    throw _errorFor(response);
  }

  /// Like [_send], for an authenticated GET whose response is raw bytes
  /// rather than JSON (an attachment or an avatar fetch): the same one-shot
  /// refresh-and-retry and error mapping, without a JSON decode that would
  /// only fail on a body that was never JSON to begin with.
  Future<FetchedBytes> _fetchBytes(String path, {bool isRetry = false}) async {
    final uri = _requestUri(path, null);
    final request = http.Request('GET', uri);
    final token = session.tokens?.accessToken;
    if (token == null) {
      throw const UnauthorizedException('not signed in');
    }
    request.headers['authorization'] = 'Bearer $token';

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } catch (e) {
      throw TransportException('GET $path failed: $e');
    }

    if (response.statusCode == 401 && !isRetry && session.tokens != null) {
      await refresh();
      return _fetchBytes(path, isRetry: true);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return FetchedBytes(
        bytes: response.bodyBytes,
        contentType:
            response.headers['content-type'] ?? 'application/octet-stream',
      );
    }
    throw _errorFor(response);
  }

  /// Turns an already-interpolated [path] (e.g.
  /// `/messages/$messageId/reactions/$emoji`) into a request [Uri] without
  /// letting a wire-supplied value decide which resource it reaches.
  ///
  /// [Uri.replace]'s `path` parameter resolves `.`/`..` segments per RFC
  /// 3986, including a percent-encoded pair (`%2e%2e` reads the same as
  /// `..`), so a value this file did not choose - an emoji string, say -
  /// can walk the request off the endpoint that built it. Splitting on the
  /// literal `/` this file wrote and handing the pieces to `pathSegments`
  /// closes that for every segment: each piece is then one opaque value,
  /// so an embedded `/`, `%`, or non-ASCII byte in it can never introduce a
  /// new separator. `pathSegments` still resolves a piece that is *exactly*
  /// `.` or `..` the same way `path` does, so [_withoutDotSegment] escapes
  /// only those two literal values; every other segment renders exactly as
  /// `pathSegments` already renders it today.
  Uri _requestUri(String path, Map<String, String>? query) {
    final parts = path.split('/');
    final segments =
        (parts.isNotEmpty && parts.first.isEmpty ? parts.skip(1) : parts)
            .map(_withoutDotSegment)
            .toList(growable: false);
    return baseUrl.replace(pathSegments: segments, queryParameters: query);
  }

  ApiException _errorFor(http.Response response) {
    var reason = 'request failed';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['error'] is String) {
        reason = decoded['error'] as String;
      }
    } catch (_) {
      // A non-JSON body is not itself an error worth surfacing; the status is.
    }
    return switch (response.statusCode) {
      400 => BadRequestException(reason),
      401 => UnauthorizedException(reason),
      403 => ForbiddenException(reason),
      404 => NotFoundException(reason),
      409 => ConflictException(reason),
      429 => RateLimitedException(reason),
      501 => NotConfiguredException(reason),
      503 => UnavailableException(reason),
      _ => ServerException(reason, response.statusCode),
    };
  }
}

/// `.` and `..` are the only two path segments [Uri] resolves away per RFC
/// 3986, even when a segment arrives through `pathSegments` rather than a
/// raw `path` string; escaping just their dots leaves every other segment
/// exactly as `pathSegments` already renders it.
String _withoutDotSegment(String segment) => (segment == '.' || segment == '..')
    ? segment.replaceAll('.', '%2E')
    : segment;
