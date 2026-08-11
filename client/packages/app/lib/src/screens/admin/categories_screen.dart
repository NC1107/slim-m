// SPDX-License-Identifier: Apache-2.0
/// Channel category management: `POST /categories`,
/// `PATCH /categories/{id}`, `DELETE /categories/{id}`. Requires
/// MANAGE_CHANNELS - the rail-management surface a category is part of, per
/// docs/decisions/0006-channel-categories.md.
///
/// Reads the local store's own category stream rather than a fresh REST
/// fetch: categories already sync there on every channel refresh
/// (`ChannelRefresher.refresh`), the same list the rail itself renders.
///
/// Reordering categories themselves (not their channels, which the rail's
/// own drag already covers - see `channel_rail_reorder.dart`) lives here
/// rather than in the rail: dragging a category's whole header block through
/// the rail's flat, single-list `ReorderableChannelRows` would risk silently
/// reassigning the channels it passed over to the dragged category, since
/// that widget attributes every channel to whichever header precedes it.
/// This screen has no channels in it at all, so a drag here can only ever
/// mean "these are the categories, in this order" - see `category_reorder.dart`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' show SlimmApiChannelAdmin;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../../providers/channel_order_controller.dart';
import '../../providers/providers.dart';
import '../../routing/routes.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/run_guarded.dart';
import '../../widgets/settings_section_header.dart';
import '../settings_screen_scaffold.dart';
import 'category_reorder.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(storeProvider);
    final orderState = ref.watch(categoryOrderControllerProvider);
    final orderController = ref.read(categoryOrderControllerProvider.notifier);

    // No padding override: the frame's own default is the inset here, matching every other admin screen.
    return SettingsScreenScaffold(
      title: 'Channel categories',
      backTooltip: 'Back to Space settings',
      backFallback: Routes.spaceSettings,
      child: storeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            const Center(child: Text('Could not load categories.')),
        data: (store) => StreamBuilder<List<ChannelCategoryRow>>(
          stream: store.watchCategories(),
          builder: (context, snapshot) {
            final categories = withPendingCategoryOrder(
              snapshot.data ?? const <ChannelCategoryRow>[],
              orderState.pendingOrder,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _CreateCategoryCard(),
                const SizedBox(height: AppSpacing.s16),
                if (orderState.error != null) ...[
                  AppErrorState(
                    message: orderState.error!,
                    onRetry: () => unawaited(orderController.retry()),
                    onDismiss: orderController.dismiss,
                  ),
                  const SizedBox(height: AppSpacing.s16),
                ],
                if (categories.isEmpty)
                  Text(
                    'No categories yet. A channel with none sits in the '
                    'rail\'s implicit uncategorised section.',
                    style: AppText.caption.copyWith(
                      color: Theme.of(
                        context,
                      ).extension<AppTokens>()!.textSecondary,
                    ),
                  )
                else
                  SettingsSectionCard(
                    title: 'Categories',
                    children: [
                      CategoryList(
                        categories: categories,
                        onReorder: (ids) =>
                            unawaited(orderController.reorder(ids)),
                        rowBuilder: (category, dragIndex) => _CategoryRow(
                          category: category,
                          dragIndex: dragIndex,
                        ),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CreateCategoryCard extends ConsumerStatefulWidget {
  const _CreateCategoryCard();

  @override
  ConsumerState<_CreateCategoryCard> createState() =>
      _CreateCategoryCardState();
}

class _CreateCategoryCardState extends ConsumerState<_CreateCategoryCard>
    with GuardedActionState<_CreateCategoryCard> {
  final _name = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _submitting = true);
    final ok = await guard(
      whatFailed: 'create the category',
      action: () async {
        final category = await ref.read(apiProvider).createCategory(name);
        final store = await ref.read(storeProvider.future);
        await store.upsertCategory(category);
      },
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) _name.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: 'New category',
      children: [
        Row(
          children: [
            Expanded(
              child: AppInput(
                controller: _name,
                placeholder: 'New category name',
                onSubmitted: (_) => _submitting ? null : _create(),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            AppButton(label: 'Create', onPressed: _submitting ? null : _create),
          ],
        ),
        if (actionError != null) ...[
          const SizedBox(height: AppSpacing.s8),
          AppErrorState(message: actionError!, onDismiss: clearActionError),
        ],
      ],
    );
  }
}

class _CategoryRow extends ConsumerStatefulWidget {
  const _CategoryRow({required this.category, this.dragIndex});

  final ChannelCategoryRow category;

  /// This row's position in the enclosing `ReorderableListView`, or null
  /// when there are fewer than two categories and so no handle to draw -
  /// see `CategoryList`'s own bail-out in `category_reorder.dart`.
  final int? dragIndex;

  @override
  ConsumerState<_CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends ConsumerState<_CategoryRow>
    with GuardedActionState<_CategoryRow> {
  late final _name = TextEditingController(text: widget.category.name);
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    final name = _name.text.trim();
    if (name.isEmpty || name == widget.category.name) return;
    setState(() => _busy = true);
    final ok = await guard(
      whatFailed: 'rename the category',
      action: () async {
        final updated = await ref
            .read(apiProvider)
            .updateCategory(categoryId: widget.category.id, name: name);
        final store = await ref.read(storeProvider.future);
        await store.upsertCategory(updated);
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) _name.text = widget.category.name;
  }

  Future<void> _delete() async {
    final confirmed = await confirmDangerousAction(
      context,
      title: 'Delete "${widget.category.name}"?',
      message:
          'Its channels are never deleted with it - they fall back to '
          'uncategorised. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    await guard(
      whatFailed: 'delete the category',
      action: () async {
        await ref.read(apiProvider).deleteCategory(widget.category.id);
        final store = await ref.read(storeProvider.future);
        await store.removeCategory(widget.category.id);
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    // Padding matches SettingsEntityRow's own outer spacing; no headline/actions split fits an editable field.
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (widget.dragIndex case final index?) ...[
                CategoryDragHandle(index: index, name: widget.category.name),
                const SizedBox(width: AppSpacing.s8),
              ],
              Expanded(
                child: AppInput(
                  controller: _name,
                  onSubmitted: (_) => _busy ? null : _rename(),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              AppIconButton(
                icon: AppIcons.check,
                semanticLabel: 'Save name',
                onPressed: _busy ? null : _rename,
              ),
              AppIconButton(
                icon: AppIcons.delete,
                semanticLabel: 'Delete category',
                variant: AppIconButtonVariant.danger,
                onPressed: _busy ? null : _delete,
              ),
            ],
          ),
          if (actionError != null) ...[
            const SizedBox(height: AppSpacing.s8),
            AppErrorState(message: actionError!, onDismiss: clearActionError),
          ],
        ],
      ),
    );
  }
}
