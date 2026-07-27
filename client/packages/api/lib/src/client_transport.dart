// SPDX-License-Identifier: Apache-2.0
part of 'client.dart';

/// The only code in this package that speaks HTTP.
///
/// Every typed method in every other part of [SlimmApi] is a wrapper over
/// [SlimmApi._send] or [SlimmApi._fetchBytes], which is why the one-shot
/// refresh-and-replay and the status-to-exception mapping are written once,
/// here, rather than per endpoint.
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
    final uri = baseUrl.replace(path: path, queryParameters: query);
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
            'could not decode the reply to $method $path: $e');
      }
    }
    throw _errorFor(response);
  }

  /// Like [_send], for an authenticated GET whose response is raw bytes
  /// rather than JSON (an attachment or an avatar fetch): the same one-shot
  /// refresh-and-retry and error mapping, without a JSON decode that would
  /// only fail on a body that was never JSON to begin with.
  Future<FetchedBytes> _fetchBytes(String path, {bool isRetry = false}) async {
    final uri = baseUrl.replace(path: path);
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
