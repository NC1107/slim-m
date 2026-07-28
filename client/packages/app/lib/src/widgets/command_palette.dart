// SPDX-License-Identifier: Apache-2.0
/// The command palette: a floating search over channels, members, messages
/// and actions, opened by `Ctrl K` or by tapping the rail's search field.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

import '../providers/member_presence.dart' show membersProvider;
import '../providers/providers.dart';
import 'channel_rail.dart' show selectedChannelId;
import 'command_palette_items.dart';

/// The design's floating card width; not on the spacing grid because it is
/// the palette's own measured size, like the rail widths beside it.
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
    barrierColor: const Color(0x8A000000),
    transitionDuration: const Duration(milliseconds: 120),
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
      setState(() => _messageResults = const []);
      return;
    }
    _search(channelId, value);
  }

  Future<void> _search(String channelId, String query) async {
    final generation = ++_searchGeneration;
    try {
      final results = await ref
          .read(apiProvider)
          .searchMessages(channelId, q: query, limit: paletteResultLimit);
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _messageResults = results);
    } on api.ApiException {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _messageResults = const []);
    }
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
    final selfId = ref.watch(meProvider).valueOrNull?.id;

    return Align(
      alignment: const Alignment(0, -0.5),
      child: CallbackShortcuts(
        bindings: _bindings(),
        child: Material(
          type: MaterialType.transparency,
          child: AppMenu(
            width: _paletteWidth,
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
                    return _buildResults(tokens, channels, members, selfId);
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
    String? selfId,
  ) {
    final groups = <(String, List<PaletteResultItem>)>[
      ('Channels', buildChannelItems(channels, _query)),
      ('Members', buildMemberItems(members, _query, selfId)),
      if (widget.currentChannelId != null)
        ('Messages', buildMessageItems(_messageResults, tokens)),
      ('Actions', buildActionItems(_query)),
    ].where((g) => g.$2.isNotEmpty).toList();

    final flat = [for (final group in groups) ...group.$2];
    _visible = flat;
    if (_highlighted >= flat.length) {
      _highlighted = flat.isEmpty ? 0 : flat.length - 1;
    }

    if (flat.isEmpty) {
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

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _resultsMaxHeight),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }
}
