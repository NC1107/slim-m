// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
import 'package:test/test.dart';
import 'package:slimm_api/api.dart' as api;

Map<String, dynamic> _baseMessage() => {
      'id': 'm1',
      'channel_id': 'c1',
      'author_id': 'u1',
      'author_display_name': 'Nia',
      'seq': 1,
      'content': '',
      'created_at': 0,
      'edited_at': null,
    };

void main() {
  test('Message.fromJson reads app_surface', () {
    final message = api.Message.fromJson({
      ..._baseMessage(),
      'app_surface': {'module_id': 'game-of-life', 'command': 'life'},
    });
    expect(message.appSurface, isNotNull);
    expect(message.appSurface!.moduleId, 'game-of-life');
    expect(message.appSurface!.command, 'life');
  });

  test('Message.fromJson leaves app_surface null when absent or null', () {
    expect(api.Message.fromJson(_baseMessage()).appSurface, isNull);
    expect(
      api.Message.fromJson({..._baseMessage(), 'app_surface': null}).appSurface,
      isNull,
    );
  });

  test('App.fromJson reads the discovery shape', () {
    final app = api.App.fromJson({
      'module_id': 'game-of-life',
      'command': 'life',
      'name': 'Game of Life',
      'description': 'Launch a board',
    });
    expect(app.moduleId, 'game-of-life');
    expect(app.command, 'life');
    expect(app.name, 'Game of Life');
    expect(app.description, 'Launch a board');
  });
}
