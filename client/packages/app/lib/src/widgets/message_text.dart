// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Rendering a message body: fenced code, headings, quotes, lists, inline
/// markdown, mentions, and the deployment's own `:shortcode:` emoji.
///
/// Inline nesting (`**bold with *italic* inside**`) comes from
/// `message_inline.dart`'s recursive-descent parser; this file walks its tree
/// into `InlineSpan`s and is where the leaf tokens that need data (mention,
/// role mention, emoji) get resolved against what this message actually has.
///
/// There is no mention *highlighting* protocol on the wire; deciding whether
/// an `@name` token becomes a chip is a client-side judgement, applied to an
/// `@name` that matches a real, currently-known member's username, or to the
/// two reserved words `@everyone`/`@here` (`push::recipients` in
/// `crates/slimm-server`, gated there on `Perm.mentionEveryone` - rendering a
/// chip here does not imply the sender actually held it, only that the word
/// is one the server recognises). An `@` that matches neither renders as
/// plain text, so nothing here invents a person who is not real. An
/// `@[Role Name]` token follows the identical rule against a currently-known
/// role name instead - see [_isRenderableRole].
///
/// A `:shortcode:` resolves the same way and for the same reason: only a name
/// the deployment actually holds becomes an image, and everything else stays
/// the text that was typed.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:slimm_design_system/design_system.dart';

import 'custom_emoji_image.dart';
import 'message_code_lexer.dart';
import 'message_fences.dart';
import 'message_inline.dart';
import 'message_markdown_blocks.dart';
import 'message_spoiler.dart';

/// One line tall: [AppText.body] is 15px at a 1.45 line height, so an inline
/// emoji is that product rather than a pixel value chosen to look right.
/// [CustomEmojiImage] defaults to the picker's 20; running text is not the
/// picker, so it says what it needs.
final double _emojiSize = AppText.body.fontSize! * AppText.body.height!;

/// A message body: fenced code blocks rendered through [AppCodeBlock], and
/// everything else split into headings, quotes, lists and paragraphs, each
/// carrying its own nested inline markdown. [knownUsernames] should be
/// lower-cased; pass an empty set while the member list has not loaded rather
/// than guessing.
class MessageBody extends StatelessWidget {
  const MessageBody({
    super.key,
    required this.content,
    required this.knownUsernames,
    this.knownRoleNames = const {},
    this.customEmoji = const {},
    this.dim = false,
    this.announceSending = false,
  });

  final String content;
  final Set<String> knownUsernames;

  /// Lower-cased role name to render an `@[Role Name]` token as a chip.
  /// Defaulted to empty (every caller that has not been given a member
  /// roster to derive it from) rather than required, so a role mention
  /// simply renders as plain text until one is supplied - the same fallback
  /// [knownUsernames] would want but cannot have, since that one is already
  /// load-bearing for every existing caller and test.
  final Set<String> knownRoleNames;

  /// Lower-cased emoji name to emoji id, from `customEmojiIndexProvider`.
  /// Defaulted rather than required so a caller with no emoji to resolve
  /// (and every existing test) renders shortcodes as the plain text they are.
  final Map<String, String> customEmoji;

  /// True for a pending or failed send, which reads as provisional rather
  /// than delivered.
  final bool dim;

  /// True only while still sending: dims the same way [dim] does, and also
  /// gives the body a "Sending" semantics label, since [dim] on its own is a
  /// sighted-only cue - a screen reader reading this body's text got nothing
  /// distinguishing it from an already-delivered message. Deliberately not
  /// merged with [dim] itself: a caller dimming for some other reason
  /// (there is none today) must not also announce a delivery state that
  /// is not true.
  final bool announceSending;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    // Provisional-to-delivered ink lerps rather than snapping on confirm.
    final body = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: dim ? 1.0 : 0.0),
      duration: AppMotion.reduced(context, AppMotion.base),
      curve: AppMotion.entrance,
      builder: (context, t, _) {
        final baseColor = Color.lerp(
          tokens.textPrimary,
          tokens.textSecondary,
          t,
        )!;

        final widgets = <Widget>[];
        for (final block in splitMessageBlocks(content)) {
          switch (block) {
            case TextBlock(:final text):
              for (final md in splitMarkdownBlocks(text)) {
                widgets.add(
                  _buildMarkdownBlock(
                    md,
                    knownUsernames: knownUsernames,
                    knownRoleNames: knownRoleNames,
                    customEmoji: customEmoji,
                    color: baseColor,
                  ),
                );
              }
            case CodeBlock(:final language, :final code):
              widgets.add(
                AppCodeBlock(
                  language: language,
                  lines: lexCodeBlock(code, language),
                ),
              );
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < widgets.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.s4),
              widgets[i],
            ],
          ],
        );
      },
    );

    // Its own container node: this body's several blocks already carry their own semantics, so a non-container label would have nowhere unambiguous to merge into.
    return announceSending
        ? Semantics(container: true, label: 'Sending', child: body)
        : body;
  }
}

/// Picks the type step and rendering shell for one [MarkdownBlock], then
/// hands its text to [_MessageTextRun] for inline parsing. Only headings
/// change the type style, from the scale's own three largest steps, never an
/// invented size.
Widget _buildMarkdownBlock(
  MarkdownBlock block, {
  required Set<String> knownUsernames,
  required Set<String> knownRoleNames,
  required Map<String, String> customEmoji,
  required Color color,
}) {
  switch (block) {
    case ParagraphBlock(:final text):
      return _MessageTextRun(
        text: text,
        knownUsernames: knownUsernames,
        knownRoleNames: knownRoleNames,
        customEmoji: customEmoji,
        color: color,
      );
    case HeadingBlock(:final level, :final text):
      final style = switch (level) {
        1 => AppText.title,
        2 => AppText.heading,
        _ => AppText.body,
      }.copyWith(fontWeight: AppWeights.semi);
      return _MessageTextRun(
        text: text,
        knownUsernames: knownUsernames,
        knownRoleNames: knownRoleNames,
        customEmoji: customEmoji,
        color: color,
        baseStyle: style,
      );
    case QuoteBlock(:final text):
      return MarkdownQuote(
        child: _MessageTextRun(
          text: text,
          knownUsernames: knownUsernames,
          knownRoleNames: knownRoleNames,
          customEmoji: customEmoji,
          color: color,
        ),
      );
    case ListBlock(:final ordered, :final items):
      return MarkdownList(
        ordered: ordered,
        items: items,
        children: [
          for (final item in items)
            _MessageTextRun(
              text: item.text,
              knownUsernames: knownUsernames,
              knownRoleNames: knownRoleNames,
              customEmoji: customEmoji,
              color: color,
            ),
        ],
      );
  }
}

/// One run of text with inline markdown, mentions and custom emoji picked
/// out. [baseStyle] carries size and weight; [color] is applied on top of it
/// so dimmed (pending/failed) messages still work at any heading level.
class _MessageTextRun extends StatefulWidget {
  const _MessageTextRun({
    required this.text,
    required this.knownUsernames,
    required this.knownRoleNames,
    required this.customEmoji,
    required this.color,
    this.baseStyle = AppText.body,
  });

  final String text;
  final Set<String> knownUsernames;
  final Set<String> knownRoleNames;
  final Map<String, String> customEmoji;
  final Color color;
  final TextStyle baseStyle;

  @override
  State<_MessageTextRun> createState() => _MessageTextRunState();
}

class _MessageTextRunState extends State<_MessageTextRun> {
  /// Link tap recognizers built for the current spans. A `TextSpan`'s
  /// recognizer is not disposed for you, so they are owned here, rebuilt on
  /// each build and released in [dispose] - a link inside a message row that
  /// scrolls off would otherwise leak one per rebuild.
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _makeLinkRecognizer(String url) {
    final recognizer = TapGestureRecognizer()..onTap = () => _open(url);
    _recognizers.add(recognizer);
    return recognizer;
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    // Parsed defensively though _urlPattern already guarantees an http(s) scheme; a link should never open anything else.
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final style = widget.baseStyle.copyWith(color: widget.color);
    return Text.rich(
      TextSpan(
        style: style,
        children: _buildSpans(
          parseInline(widget.text),
          _InlineContext(
            knownUsernames: widget.knownUsernames,
            knownRoleNames: widget.knownRoleNames,
            customEmoji: widget.customEmoji,
            ambientStyle: style,
            linkColor: tokens.accent,
            makeLinkRecognizer: _makeLinkRecognizer,
          ),
        ),
      ),
    );
  }
}

/// The two reserved mentions `crates/slimm-server/src/push/recipients.rs`
/// resolves specially, never a real account (`validate_username` in
/// `http/auth.rs` refuses to register either, case-insensitively) - kept
/// lower-case, matched the same way against a lower-cased [raw].
const _reservedMentions = {'everyone', 'here'};

/// Whether [raw] (the whole `@name` token, `@` included) should render as a
/// chip: either it names someone in [knownUsernames], or it is one of the
/// two reserved words above. Rendering a reserved word as a chip says
/// nothing about whether the sender actually held `Perm.mentionEveryone` -
/// that permission only ever gates who gets woken for it, never whether the
/// word itself is recognised - so it is drawn the same way regardless.
bool _isRenderableMention(String raw, Set<String> knownUsernames) {
  final name = raw.substring(1).toLowerCase();
  return knownUsernames.contains(name) || _reservedMentions.contains(name);
}

/// Whether [name] (already brackets-stripped) should render as a role chip:
/// it names a role in [knownRoleNames]. Unlike [_isRenderableMention] there
/// is no reserved-word fallback - `@[everyone]` is a literal role name, not
/// the mass mention, and `roles_for_names` on the server refuses to resolve
/// it for exactly that reason; see its own doc comment.
bool _isRenderableRole(String name, Set<String> knownRoleNames) =>
    knownRoleNames.contains(name.toLowerCase());

/// Walks a [parseInline] tree into `InlineSpan`s. Bold, italic and
/// strikethrough are a style diff on a wrapping [TextSpan]; Flutter merges a
/// child span's style onto its parent's at paint time, which is the whole
/// mechanism nesting rides on: an [InlineBold] wrapping an [InlineItalic]
/// needs no combined style computed here, each node states only its own diff.
/// Everything [_buildSpans] needs beyond the nodes themselves, bundled so the
/// recursion passes one value rather than six and so a link can reach both
/// its colour and the recognizer owner that will dispose it.
class _InlineContext {
  const _InlineContext({
    required this.knownUsernames,
    required this.knownRoleNames,
    required this.customEmoji,
    required this.ambientStyle,
    required this.linkColor,
    required this.makeLinkRecognizer,
  });

  final Set<String> knownUsernames;
  final Set<String> knownRoleNames;
  final Map<String, String> customEmoji;
  final TextStyle ambientStyle;
  final Color linkColor;

  /// Creates a tap recognizer for [url] and hands it to whoever owns the
  /// run's lifecycle, so it is disposed with the widget rather than leaked.
  final TapGestureRecognizer Function(String url) makeLinkRecognizer;
}

List<InlineSpan> _buildSpans(List<InlineNode> nodes, _InlineContext ctx) => [
  for (final node in nodes)
    switch (node) {
      InlineText(:final text) => TextSpan(text: text),
      InlineCode(:final text) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: AppInlineCode(text),
      ),
      InlineMention(:final raw) =>
        _isRenderableMention(raw, ctx.knownUsernames)
            ? WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _MentionChip(raw),
              )
            : TextSpan(text: raw),
      InlineRoleMention(:final name) =>
        _isRenderableRole(name, ctx.knownRoleNames)
            ? WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _MentionChip('@$name'),
              )
            : TextSpan(text: '@[$name]'),
      InlineEmoji(:final raw) => _emojiSpan(raw, ctx.customEmoji),
      InlineLink(:final url) => TextSpan(
        text: url,
        style: TextStyle(
          color: ctx.linkColor,
          decoration: TextDecoration.underline,
          decorationColor: ctx.linkColor,
        ),
        recognizer: ctx.makeLinkRecognizer(url),
        mouseCursor: SystemMouseCursors.click,
      ),
      InlineBold(:final children) => TextSpan(
        style: const TextStyle(fontWeight: AppWeights.semi),
        children: _buildSpans(children, ctx),
      ),
      InlineItalic(:final children) => TextSpan(
        style: const TextStyle(fontStyle: FontStyle.italic),
        children: _buildSpans(children, ctx),
      ),
      InlineStrikethrough(:final children) => TextSpan(
        style: const TextStyle(decoration: TextDecoration.lineThrough),
        children: _buildSpans(children, ctx),
      ),
      InlineSpoiler(:final children) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: MessageSpoiler(
          style: ctx.ambientStyle,
          spans: _buildSpans(children, ctx),
        ),
      ),
    },
];

InlineSpan _emojiSpan(String raw, Map<String, String> customEmoji) {
  final id = customEmojiIdFor(raw, customEmoji);
  return id == null
      ? TextSpan(text: raw)
      : WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: CustomEmojiImage(emojiId: id, label: raw, size: _emojiSize),
        );
}

/// `--accent-text` on `--accent-soft`, matching the design's mention pill.
/// Not a design-system component: a mention is a message-body decoration
/// specific to this screen, not a control other surfaces reuse.
class _MentionChip extends StatelessWidget {
  const _MentionChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Text(
        text,
        style: AppText.body.copyWith(
          color: tokens.accent,
          fontWeight: AppWeights.medium,
        ),
      ),
    );
  }
}
