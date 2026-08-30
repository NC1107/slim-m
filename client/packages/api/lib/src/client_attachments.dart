// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
part of 'client.dart';

/// Attachments: upload bytes once, reference the returned id in
/// [SlimmApi.sendMessage], fetch them back. The `attachments` tag.
extension SlimmApiAttachments on SlimmApi {
  /// Uploads an attachment's raw [bytes]. Idempotent by content: uploading
  /// bytes that already exist returns the existing id rather than storing a
  /// second copy. An id never referenced by a message is reclaimed
  /// automatically after a day, so upload right before sending rather than
  /// far ahead of it.
  Future<Attachment> uploadAttachment(
    List<int> bytes, {
    String? filename,
  }) async {
    final json = await _send(
      'POST',
      '/attachments',
      bytes: bytes,
      query: filename == null ? null : {'filename': filename},
    );
    return Attachment.fromJson(json as Map<String, dynamic>);
  }

  /// Fetches an attachment's raw bytes. Requires viewing a channel that has a
  /// live message attaching it, checked across every channel that does,
  /// since content addressing means more than one message can share the
  /// same bytes.
  Future<FetchedBytes> fetchAttachment(String attachmentId) =>
      _fetchBytes('/attachments/$attachmentId');

  /// The same endpoint [fetchAttachment] reads, for a caller that streams the
  /// bytes itself rather than loading them into memory - a native video
  /// player, which can attach `session.tokens?.accessToken` as its own
  /// bearer header and let the player issue range requests directly. Carries
  /// no token itself: this is only the address.
  Uri attachmentUrl(String attachmentId) =>
      _requestUri('/attachments/$attachmentId', null);
}
