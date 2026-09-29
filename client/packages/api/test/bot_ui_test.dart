// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Menu entries and call controls a bot registers, as the client reads them
/// and sends their use. See docs/decisions/0045-bot-contributed-ui.md.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

SlimmApi _client(MockClient http) => SlimmApi(
      baseUrl: Uri.parse('http://localhost:8080'),
      session: SessionStore(
        tokens: const TokenPair(
          userId: 'u1',
          accessToken: 'a',
          refreshToken: 'r',
          accessExpiresAt: 4102444800000,
        ),
      ),
      httpClient: http,
    );

void main() {
  test('reads each bot with its menu entries and call controls', () async {
    final api = _client(
      MockClient((request) async {
        expect(request.url.path, '/channels/c1/bot-ui');
        return http.Response(
          jsonEncode([
            {
              'bot_user_id': 'b1',
              'bot_username': 'helper',
              'bot_display_name': 'Helper',
              'message_menu': [
                {'id': 'translate', 'label': 'Translate'},
              ],
              'call_controls': [
                {'id': 'pause', 'label': 'Pause', 'icon': 'pause'},
              ],
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final bots = await api.listChannelBotUi('c1');
    expect(bots.single.botDisplayName, 'Helper');
    expect(bots.single.messageMenu.single.label, 'Translate');
    expect(bots.single.messageMenu.single.icon, isNull);
    expect(bots.single.callControls.single.icon, 'pause');
  });

  test('a menu entry names its message and a control names none', () async {
    final bodies = <Map<String, dynamic>>[];
    final paths = <String>[];
    final api = _client(
      MockClient((request) async {
        paths.add(request.url.path);
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({'id': 'x', 'created_at': 1}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await api.useBotMenuEntry(
      channelId: 'c1',
      botId: 'b1',
      entryId: 'translate',
      messageId: 'm1',
      id: 'i1',
    );
    await api.useBotCallControl(
      channelId: 'c1',
      botId: 'b1',
      entryId: 'pause',
      id: 'i2',
    );
    expect(paths, everyElement('/channels/c1/bot-ui/b1/interactions'));
    expect(bodies[0], {
      'id': 'i1',
      'surface': 'message_menu',
      'entry_id': 'translate',
      'message_id': 'm1',
    });
    expect(bodies[1], {
      'id': 'i2',
      'surface': 'call_control',
      'entry_id': 'pause',
    });
  });

  test('interaction.answered parses without a message id', () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'interaction.answered',
        'interaction_id': 'i1',
        'channel_id': 'c1',
      }),
    );
    expect(event, isA<InteractionAnswered>());
    expect((event as InteractionAnswered).messageId, isNull);
  });
}
