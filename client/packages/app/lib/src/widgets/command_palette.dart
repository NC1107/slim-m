// SPDX-License-Identifier: Apache-2.0
/// The command palette: a floating search over channels, members, messages
/// and actions, opened by `Ctrl K` or by tapping the rail's search field.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

import '../providers/admin_providers.dart';
import '../routing/modal_page.dart';
import '../providers/member_presence.dart' show membersProvider;
import '../providers/message_search.dart';
import '../providers/personal_space_visibility.dart';
import '../providers/providers.dart';
import '../providers/user_profiles.dart';
import 'channel_rail.dart' show selectedChannelId;
import 'command_palette_items.dart';

/// The design's floating card width; not on the spacing grid because it is
/// the palette's own measured size, like the rail widths beside it. Clamped
/// per build against the viewport (see [_CommandPaletteContentState.build])
/// - this is the one overlay in the app that never adopted `showAppSheet`'s
/// phone/desktop split, so the fixed 480 overflowed a 390-wide phone
/// symmetrically by 45px a side, cropping the leading edge of every row.
const double _paletteWidth = 480;
const double _resultsMaxHeight = 360;

/// Opens the palette over whatever is on screen, scoping message search to
/// the channel already open (there is no cross-channel search endpoint), and
/// restores focus to wherever it was once the palette closes.
Future<void> openCommandPalette(BuildContext context) async {
  final previousFocus = FocusManager.instance.primaryFocus;
  final channelId = selectedChannelId(context);

  await showGeneralDialog<void>(
    context: context,
    barrierLabel: 'Command palette',
    barrierDismissible: true,
    barrierColor: kScrimColor,
    transitionDuration: AppMotion.reduced(context, AppMotion.fast),
    pageBuilder: (context, animation, secondaryAnimation) =>
        _CommandPaletteContent(currentChannelId: channelId),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
  );

  // The dialog may have outlived whatever held focus before it opened, so only
  // claim it back if it is still attached to something that can take it.
  if (previousFocus != null && previousFocus.context != null) {
    previousFocus.requestFocus();
  }
}

class _CommandPaletteContent extends ConsumerStatefulWidget {
  const _CommandPaletteContent({required this.currentChannelId});

  final String? currentChannelId;

  @override
  ConsumerState<_CommandPaletteContent> createState() =>
      _CommandPaletteContentState();
}

class _CommandPaletteContentState
    extends ConsumerState<_CommandPaletteContent> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';
  int _highlighted = 0;
  List<api.Message> _messageResults = const [];

  /// Whether the last message search came back as a 403 rather than a
  /// genuinely empty result; the two must not read the same.
  bool _messagesForbidden = false;

  /// Guards against a fast typist's earlier request resolving after a later
  /// one and clobbering its results, since there is no debounce here (the
  /// channel search bar this mirrors has none either).
  int _searchGeneration = 0;

  /// The last frame's flat result list, so a key handler (which runs outside
  /// build) can act on exactly what the user is looking at right now.
  List<PaletteResultItem> _visible = const [];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _highlighted = 0;
    });
    final channelId = widget.currentChannelId;
    if (value.isEmpty || channelId == null) {
      setState(() {
        _messageResults = const [];
        _messagesForbidden = false;
      });
      return;
    }
    _search(channelId, value);
  }

  /// The same call `channelSearchProvider` makes, through the one shared
  /// helper: identical blocked-author filtering, and the same 403-versus-any-
  /// other-failure distinction, so the two cannot diverge again the way they
  /// already had.
  Future<void> _search(String channelId, String query) async {
    final generation = ++_searchGeneration;
    final result = await searchChannelMessages(
      ref.read,
      channelId,
      query,
      limit: paletteResultLimit,
    );
    if (!mounted || generation != _searchGeneration) return;
    setState(() {
      switch (result) {
        case MessageSearchHits(:final messages):
          _messageResults = messages;
          _messagesForbidden = false;
        case MessageSearchForbidden():
          _messageResults = const [];
          _messagesForbidden = true;
        case MessageSearchFailed():
          _messageResults = const [];
          _messagesForbidden = false;
      }
    });
  }

  void _move(int delta) {
    if (_visible.isEmpty) return;
    setState(() {
      _highlighted = (_highlighted + delta) % _visible.length;
      if (_highlighted < 0) _highlighted += _visible.length;
    });
  }

  Future<void> _runHighlighted() async {
    if (_visible.isEmpty) return;
    await _run(_visible[_highlighted]);
  }

  Future<void> _run(PaletteResultItem item) async {
    await item.onSelect(context, ref);
    if (mounted) Navigator.of(context).pop();
  }

  Map<ShortcutActivator, VoidCallback> _bindings() {
    final close = activatorFor(AppAction.escape);
    return {
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
      if (close != null) close: () => Navigator.of(context).pop(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final storeAsync = ref.watch(storeProvider);
    final members = ref.watch(membersProvider).valueOrNull ?? const [];
    final me = ref.watch(meProvider).valueOrNull;
    final permissions = ref.watch(myPermissionsProvider);
    final personalSpaceHidden = ref.watch(personalSpaceVisibilityProvider);
    // Clamped against the viewport; see the doc comment on _paletteWidth.
    final paletteWidth = math.min(
      _paletteWidth,
      MediaQuery.sizeOf(context).width - 2 * AppSpacing.s24,
    );

    return Align(
      alignment: const Alignment(0, -0.5),
      child: CallbackShortcuts(
        bindings: _bindings(),
        child: Material(
          type: MaterialType.transparency,
          child: AppMenu(
            width: paletteWidth,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.s8),
                child: AppInput(
                  key: const Key('command-palette-input'),
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  placeholder: 'Search channels, members and messages',
                  icon: Icon(
                    AppIcons.search,
                    size: AppSizes.icon16,
                    color: tokens.textSecondary,
                  ),
                  onChanged: _onQueryChanged,
                  onSubmitted: (_) => _runHighlighted(),
                  semanticLabel: 'Search channels, members and messages',
                ),
              ),
              const AppMenuDivider(),
              storeAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (e, _) => const SizedBox.shrink(),
                data: (store) => StreamBuilder<List<Channel>>(
                  stream: store.watchChannels(),
                  builder: (context, snapshot) {
                    final channels = snapshot.data ?? const <Channel>[];
                    return _buildResults(
                      tokens,
                      channels,
                      members,
                      me,
                      permissions,
                      personalSpaceHidden,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(
    AppTokens tokens,
    List<Channel> channels,
    List<api.UserProfile> members,
    api.Me? me,
    int permissions,
    bool personalSpaceHidden,
  ) {
    final profiles = ref.watch(batchProfilesControllerProvider);
    resolveAuthorProfiles(ref, _messageResults.map((m) => m.authorId));
    final groups = <(String, List<PaletteResultItem>)>[
      (
        'Channels',
        buildChannelItems(
          channels,
          _query,
          selfDisplayName: me?.displayName,
          personalSpaceHidden: personalSpaceHidden,
        ),
      ),
      ('Members', buildMemberItems(members, _query, me?.id)),
      if (widget.currentChannelId != null && !_messagesForbidden)
        (
          'Messages',
          buildMessageItems(
            _messageResults,
            tokens,
            currentChannelId: widget.currentChannelId,
            profiles: profiles,
          ),
        ),
      ('Actions', buildActionItems(_query, permissions)),
    ].where((g) => g.$2.isNotEmpty).toList();

    // An empty result and a refusal are different things; so says search too.
    final showForbiddenNotice =
        widget.currentChannelId != null &&
        _messagesForbidden &&
        _query.isNotEmpty;

    final flat = [for (final group in groups) ...group.$2];
    _visible = flat;
    if (_highlighted >= flat.length) {
      _highlighted = flat.isEmpty ? 0 : flat.length - 1;
    }

    if (flat.isEmpty && !showForbiddenNotice) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Text(
          'No matches.',
          style: AppText.body.copyWith(color: tokens.textSecondary),
        ),
      );
    }

    final rows = <Widget>[];
    var index = 0;
    for (final group in groups) {
      rows.add(AppMenuLabel(group.$1));
      for (final item in group.$2) {
        final at = index;
        index++;
        rows.add(
          AppMenuItem(
            label: item.label,
            leading: item.leading,
            trailing: item.trailing,
            selected: at == _highlighted,
            semanticLabel: item.semanticLabel,
            onTap: () => _run(item),
          ),
        );
      }
    }
    if (showForbiddenNotice) {
      rows.add(const AppMenuLabel('Messages'));
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s8,
          ),
          child: Text(
            'You do not have permission to search this channel.',
            style: AppText.micro.copyWith(color: tokens.textSecondary),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _resultsMaxHeight),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }
}
