// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// `buildForwardedContent`: the plain-send-with-a-quote-block wire shape a
/// forward actually sends, and the reason it exists at all rather than a
/// cross-channel `reply_to_id` - see the file's own doc comment.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/forward_message.dart';

void main() {
  test('quotes every line of the content with a leading >', () {
    final content = buildForwardedContent(
      authorLabel: 'Priya',
      content: 'line one\nline two',
    );
    expect(content, 'Forwarded from Priya\n> line one\n> line two');
  });

  test('a single-line message quotes as a single line', () {
    final content = buildForwardedContent(
      authorLabel: 'Kess',
      content: 'hello there',
    );
    expect(content, 'Forwarded from Kess\n> hello there');
  });

  test('an empty message still quotes, as an empty quoted line', () {
    final content = buildForwardedContent(authorLabel: 'Dorian', content: '');
    expect(content, 'Forwarded from Dorian\n> ');
  });

  test('the attribution names the original author, not the forwarder', () {
    final content = buildForwardedContent(
      authorLabel: 'Original Author',
      content: 'their words',
    );
    expect(content, startsWith('Forwarded from Original Author'));
  });
}
