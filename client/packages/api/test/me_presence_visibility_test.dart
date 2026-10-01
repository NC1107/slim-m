// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

void main() {
  Map<String, dynamic> base() => {
        'id': 'u',
        'username': 'bob',
        'display_name': 'Bob',
        'created_at': 1,
        'permissions': 0,
      };

  test('Me reads the caller\'s stored presence choice', () {
    final me = Me.fromJson({...base(), 'presence_visibility': 'hidden'});
    expect(me.presenceVisibility, 'hidden');
  });

  test('Me from an older server that omits the field reads null', () {
    expect(Me.fromJson(base()).presenceVisibility, isNull);
  });
}
