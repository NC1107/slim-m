// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Tests for the FCM token bridge: platform gating, every shape
/// [FcmTokenSource] can answer with, and the rotation stream a caller
/// re-registers from.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_platform/platform.dart';

void main() {
  group('FcmTokenChannel.fetch', () {
    test('a non-Android platform never touches the source', () async {
      final source = _FakeFcmTokenSource(token: 'unused');

      final result =
          await FcmTokenChannel(source: source, isAndroid: false).fetch();

      expect(result, isA<FcmUnsupported>());
      expect(source.getTokenCalls, 0);
    });

    test('a token from the source is FcmTokenReady', () async {
      final source = _FakeFcmTokenSource(token: 'abcd1234');

      final result =
          await FcmTokenChannel(source: source, isAndroid: true).fetch();

      expect(result, isA<FcmTokenReady>());
      expect((result as FcmTokenReady).token, 'abcd1234');
    });

    test('a null token is FcmRegistrationFailed, not a silent no-op', () async {
      final source = _FakeFcmTokenSource(token: null);

      final result =
          await FcmTokenChannel(source: source, isAndroid: true).fetch();

      expect(result, isA<FcmRegistrationFailed>());
    });

    test('the source throwing is FcmRegistrationFailed with the reason kept',
        () async {
      final source = _FakeFcmTokenSource(error: StateError('no Play Services'));

      final result =
          await FcmTokenChannel(source: source, isAndroid: true).fetch();

      expect(result, isA<FcmRegistrationFailed>());
      expect(
        (result as FcmRegistrationFailed).reason,
        contains('no Play Services'),
      );
    });
  });

  group('FcmTokenChannel.onTokenRefresh', () {
    test('is permanently empty on a non-Android platform', () async {
      final source = _FakeFcmTokenSource(token: 'unused');
      final channel = FcmTokenChannel(source: source, isAndroid: false);

      final events = <String>[];
      final subscription = channel.onTokenRefresh.listen(events.add);
      source.rotate('new-token');
      await pumpEventQueue();
      await subscription.cancel();

      expect(events, isEmpty);
    });

    test('forwards every rotation from the source on Android', () async {
      final source = _FakeFcmTokenSource(token: 'unused');
      final channel = FcmTokenChannel(source: source, isAndroid: true);

      final events = <String>[];
      final subscription = channel.onTokenRefresh.listen(events.add);
      source.rotate('rotated-1');
      source.rotate('rotated-2');
      await pumpEventQueue();
      await subscription.cancel();

      expect(events, ['rotated-1', 'rotated-2']);
    });
  });
}

/// A [FcmTokenSource] a test fully controls: either a fixed token or a
/// thrown error, plus a rotation stream the test drives by hand, so nothing
/// here ever needs a real Firebase plugin or an Android device.
class _FakeFcmTokenSource implements FcmTokenSource {
  _FakeFcmTokenSource({this.token, this.error});

  final String? token;
  final Object? error;
  int getTokenCalls = 0;
  final _refreshController = StreamController<String>.broadcast();

  @override
  Future<String?> getToken() async {
    getTokenCalls++;
    if (error != null) throw error!;
    return token;
  }

  @override
  Stream<String> get onTokenRefresh => _refreshController.stream;

  void rotate(String newToken) => _refreshController.add(newToken);
}
