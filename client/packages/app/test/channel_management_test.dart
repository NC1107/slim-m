// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Channel rail sections and `canManage` gating: which section headers show,
/// and that a member without MANAGE_CHANNELS gets a read-only list. The
/// Channel settings screen's own round trip lives in
/// `channel_settings_management_test.dart`; the fixture both share is
/// `channel_management_harness.dart`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slimm_data/data.dart';
import 'package:slimm_app/src/widgets/channel_rail.dart' show channelIdInPath;
import 'package:slimm_app/src/widgets/channel_rail_sections.dart';

import 'channel_management_harness.dart';

void main() {
  group('section header (backlog item 55)', () {
    testWidgets('the uncategorised section reads CHANNELS, the same treatment '
        'DirectMessagesSection gives its own header - it used to be a blank '
        'label with a floating "+" and no explanation', (tester) async {
      await tester.pumpWidget(
        harness(
          ChannelCategorySections(
            channels: [channel('c1', 'general')],
            categories: const [],
            selectedId: null,
            onReorder: (_) {},
          ),
          handler: (_) => http.Response('{}', 200),
        ),
      );

      expect(find.text('CHANNELS'), findsOneWidget);
      expect(find.bySemanticsLabel('Channels'), findsOneWidget);
    });

    testWidgets('a named category keeps showing its own name above it', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          ChannelCategorySections(
            channels: [channel('c1', 'general', categoryId: 'cat-1')],
            categories: const [
              ChannelCategoryRow(id: 'cat-1', name: 'Text', position: 0),
            ],
            selectedId: null,
            onReorder: (_) {},
          ),
          handler: (_) => http.Response('{}', 200),
        ),
      );

      expect(find.text('TEXT'), findsOneWidget);
    });

    testWidgets('an empty category is hidden from a member: migration 0031 '
        'seeds Text and Voice unconditionally, so every fresh deployment '
        'rendered two dead headers under the populated one', (tester) async {
      await tester.pumpWidget(
        harness(
          ChannelCategorySections(
            channels: [channel('c1', 'general')],
            categories: const [
              ChannelCategoryRow(id: 'cat-1', name: 'Text', position: 0),
              ChannelCategoryRow(id: 'cat-2', name: 'Voice', position: 1),
            ],
            selectedId: null,
            onReorder: (_) {},
          ),
          handler: (_) => http.Response('{}', 200),
        ),
      );

      expect(find.text('CHANNELS'), findsOneWidget);
      expect(find.text('TEXT'), findsNothing);
      expect(find.text('VOICE'), findsNothing);
    });

    testWidgets('a manager keeps the empty category, as a drop target', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          ChannelCategorySections(
            channels: [channel('c1', 'general')],
            categories: const [
              ChannelCategoryRow(id: 'cat-1', name: 'Text', position: 0),
            ],
            selectedId: null,
            canManage: true,
            onReorder: (_) {},
          ),
          handler: (_) => http.Response('{}', 200),
        ),
      );

      expect(find.text('TEXT'), findsOneWidget);
    });
  });

  group('gating on canManage', () {
    testWidgets('a member without MANAGE_CHANNELS sees a read-only list', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          ChannelCategorySections(
            channels: [channel('c1', 'general')],
            categories: const [],
            selectedId: null,
            onReorder: (_) {},
          ),
          handler: (_) => http.Response('{}', 200),
        ),
      );

      expect(find.bySemanticsLabel('Manage general'), findsNothing);
    });

    testWidgets('a manager sees a per-row manage button', (tester) async {
      await tester.pumpWidget(
        harness(
          ChannelCategorySections(
            channels: [channel('c1', 'general')],
            categories: const [],
            selectedId: null,
            canManage: true,
            onReorder: (_) {},
          ),
          handler: (_) => http.Response('{}', 200),
        ),
      );

      expect(find.bySemanticsLabel('Manage general'), findsOneWidget);
    });
  });

  group('channelIdInPath', () {
    test('reads the id only from a channel route', () {
      expect(channelIdInPath('/channels/c1'), 'c1');
      expect(channelIdInPath('/channels'), isNull);
      expect(channelIdInPath('/channels/'), isNull);
      expect(channelIdInPath('/settings'), isNull);
    });
  });
}
