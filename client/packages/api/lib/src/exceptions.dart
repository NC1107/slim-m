// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Typed failures, so callers branch on what happened rather than parsing
/// status codes at every call site.
library;

/// Base for anything the API layer can fail with.
sealed class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The request never reached the server, or the reply was unreadable.
/// Retryable, and the caller cannot know whether the write landed, which is why
/// writes are keyed idempotently.
class TransportException extends ApiException {
  const TransportException(super.message);
}

/// Credentials are missing, expired, or revoked. The session should refresh
/// once and, if that also fails, sign the user out.
class UnauthorizedException extends ApiException {
  const UnauthorizedException(super.message);
}

/// The caller is authenticated but not allowed. Also returned for a channel
/// that does not exist, so absence is not distinguishable from denial.
class ForbiddenException extends ApiException {
  const ForbiddenException(super.message);
}

/// The target does not exist within a scope the caller can see.
class NotFoundException extends ApiException {
  const NotFoundException(super.message);
}

/// The request collided with existing state, for example reusing a message id
/// that already belongs to a different channel or author.
class ConflictException extends ApiException {
  const ConflictException(super.message);
}

/// The request failed validation.
class BadRequestException extends ApiException {
  const BadRequestException(super.message);
}

/// Over the rate budget for this traffic class. Back off before retrying.
class RateLimitedException extends ApiException {
  const RateLimitedException(super.message, {this.retryAfter});

  /// How long the response itself said to wait, parsed from a `Retry-After`
  /// header carrying a delay in seconds. Null when the response carried no
  /// such header (the server does not send one today) or one this could not
  /// parse, in which case a caller falls back to its own backoff.
  final Duration? retryAfter;
}

/// The server shed the request under load. Retry shortly.
class UnavailableException extends ApiException {
  const UnavailableException(super.message);
}

/// The deployment does not offer this feature at all, as opposed to offering it
/// and being briefly unable to serve it.
///
/// Distinct from [UnavailableException] because the right response is opposite:
/// hide the feature rather than retry it. A text-only self-host with no SFU is
/// a supported configuration, not a fault.
class NotConfiguredException extends ApiException {
  const NotConfiguredException(super.message);
}

/// An unexpected status, kept distinct so it is never silently treated as one
/// of the handled cases.
class ServerException extends ApiException {
  const ServerException(super.message, this.statusCode);

  final int statusCode;
}
