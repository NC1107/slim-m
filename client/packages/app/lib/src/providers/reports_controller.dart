// SPDX-License-Identifier: Apache-2.0
/// The moderation queue, one page at a time.
///
/// `GET /reports` is bounded now: it used to answer with every open report in
/// the deployment and re-check visibility channel by channel, at several
/// indexed queries each, so one request's cost was set by how many reports
/// members had filed. The queue is a work list that can outgrow a screen either
/// way, so the client pages rather than the server answering with all of it.
///
/// The one subtlety, which the server's own doc comment shares: the visibility
/// filter runs after the page is read, so a page can arrive holding fewer
/// entries than asked for, or none, while more remain. "More to load" is
/// therefore whether the *page* was full, never whether the list grew.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'providers.dart';

/// How many reports to ask for at a time. Under the server's own 200 ceiling,
/// and enough that a small deployment never sees a second page.
const int reportsPageSize = 50;

class ReportsState {
  const ReportsState({
    this.reports = const [],
    this.loading = true,
    this.error,
    this.more = false,
  });

  final List<api.Report> reports;
  final bool loading;
  final String? error;

  /// Whether the last page came back full, which is the only thing that says
  /// more may follow.
  final bool more;
}

class ReportsController extends StateNotifier<ReportsState> {
  ReportsController(this._ref) : super(const ReportsState()) {
    refresh();
  }

  final Ref _ref;

  /// Starts the queue again from the top.
  Future<void> refresh() async {
    state = const ReportsState();
    await _load(after: null, onto: const []);
  }

  /// Asks for the page after the last report already held.
  Future<void> loadMore() async {
    if (state.loading || !state.more || state.reports.isEmpty) return;
    state = ReportsState(reports: state.reports, loading: true, more: true);
    await _load(after: state.reports.last.createdAt, onto: state.reports);
  }

  Future<void> _load({
    required int? after,
    required List<api.Report> onto,
  }) async {
    try {
      final page = await _ref
          .read(apiProvider)
          .listOpenReports(after: after, limit: reportsPageSize);
      if (!mounted) return;
      state = ReportsState(
        reports: [...onto, ...page],
        loading: false,
        more: page.length >= reportsPageSize,
      );
    } on api.ApiException catch (e) {
      if (!mounted) return;
      state = ReportsState(reports: onto, loading: false, error: e.message);
    }
  }
}

final reportsControllerProvider =
    StateNotifierProvider.autoDispose<ReportsController, ReportsState>(
      (ref) => ReportsController(ref),
    );
