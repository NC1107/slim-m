// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Turning on the second factor: scan or type the secret, prove a code, then
/// write down the recovery codes.
///
/// `showAppSheet`, so a bottom sheet on a phone and a centred dialog on a
/// desktop (`docs/design/desktop-vs-mobile.md`, rule 4).
///
/// Three steps in one sheet rather than three surfaces, because the middle one
/// is the whole point: nothing is enforced until a code off the authenticator is
/// verified, so a person who scans and then closes the sheet has changed nothing
/// about how they sign in. Decision 0048 has the reasoning.
///
/// The secret is shown as a QR code *and* as text. The text is not a fallback
/// for a decorative QR: a desktop showing a QR on the same screen the
/// authenticator would have to photograph is the normal case here, and typing
/// 32 characters is what that person actually does.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import '../providers/toasts.dart';
import 'run_guarded.dart';
import 'totp_recovery_codes.dart';

/// Opens the enrolment sheet. Resolves true once the factor is on, so the
/// caller can refresh whatever showed it as off.
Future<bool?> showTotpEnrolSheet(BuildContext context) =>
    showAppSheet<bool>(context, builder: (context) => const _TotpEnrolSheet());

class _TotpEnrolSheet extends ConsumerStatefulWidget {
  const _TotpEnrolSheet();

  @override
  ConsumerState<_TotpEnrolSheet> createState() => _TotpEnrolSheetState();
}

class _TotpEnrolSheetState extends ConsumerState<_TotpEnrolSheet>
    with GuardedActionState<_TotpEnrolSheet> {
  final _controller = TextEditingController();
  api.TotpEnrolment? _enrolment;
  List<String>? _recoveryCodes;
  bool _busy = false;
  String? _codeError;

  @override
  void initState() {
    super.initState();
    // On open, unlike `reset_code_sheet`: an abandoned enrolment is never enforced and the next attempt replaces it.
    Future.microtask(_begin);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    setState(() => _busy = true);
    await guard(
      whatFailed: 'start setting up two-factor authentication',
      action: () async {
        final enrolment = await ref.read(apiProvider).beginTotpEnrolment();
        if (mounted) setState(() => _enrolment = enrolment);
      },
    );
    if (mounted) setState(() => _busy = false);
  }

  String get _code => _controller.text.replaceAll(RegExp(r'\s'), '');

  Future<void> _confirm() async {
    if (_code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _codeError = null;
    });
    try {
      final codes = await ref.read(apiProvider).confirmTotpEnrolment(_code);
      if (!mounted) return;
      setState(() => _recoveryCodes = codes);
    } on api.ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _codeError = _confirmFailure(e);
        _controller.clear();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A wrong code is the ordinary case and gets its own sentence; everything
  /// else falls back to what the server said.
  String _confirmFailure(api.ApiException e) => switch (e) {
    api.BadRequestException() =>
      'That code was not accepted. Codes change every 30 seconds, so check '
          'your phone is showing the current one.',
    api.RateLimitedException() =>
      'Too many incorrect codes. Wait a few minutes and try again.',
    _ => e.message,
  };

  void _copySecret(String secret) {
    Clipboard.setData(ClipboardData(text: secret));
    ref
        .read(toastsProvider.notifier)
        .show('Setup key copied.', severity: AppToastSeverity.success);
  }

  @override
  Widget build(BuildContext context) {
    final codes = _recoveryCodes;
    if (codes != null) {
      return TotpRecoveryCodesView(
        codes: codes,
        headline: 'Two-factor authentication is on',
        onDone: () => Navigator.of(context).pop(true),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s16,
        0,
        AppSpacing.s16,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.s16,
      ),
      child: SingleChildScrollView(child: _setup(context)),
    );
  }

  Widget _setup(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final enrolment = _enrolment;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Set up two-factor authentication',
          style: AppText.body.copyWith(
            color: tokens.textPrimary,
            fontWeight: AppWeights.semi,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          'Scan this with an authenticator app, or type the key in by hand. '
          'Then enter the code it shows, so nothing is switched on until we '
          'know it works.',
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s12),
        if (enrolment == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
            child: Center(
              child: Text(
                'Preparing...',
                style: AppText.caption.copyWith(color: tokens.textSecondary),
              ),
            ),
          )
        else ...[
          _Qr(uri: enrolment.provisioningUri),
          const SizedBox(height: AppSpacing.s12),
          _SecretBlock(
            secret: enrolment.secret,
            onCopy: () => _copySecret(enrolment.secret),
          ),
          const SizedBox(height: AppSpacing.s12),
          AppInput(
            controller: _controller,
            placeholder: '000000',
            mono: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            semanticLabel: 'Code from your authenticator app',
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _confirm(),
          ),
        ],
        if (_codeError != null) ...[
          const SizedBox(height: AppSpacing.s8),
          AppErrorState(
            message: _codeError!,
            onDismiss: () => setState(() => _codeError = null),
          ),
        ],
        if (actionError != null) ...[
          const SizedBox(height: AppSpacing.s8),
          AppErrorState(message: actionError!, onRetry: _begin),
        ],
        const SizedBox(height: AppSpacing.s12),
        AppButton(
          label: _busy ? 'Checking...' : 'Turn on',
          variant: AppButtonVariant.primary,
          full: true,
          disabled: _busy || enrolment == null || _code.isEmpty,
          onPressed: _confirm,
        ),
      ],
    );
  }
}

/// The provisioning URI as a scannable square.
///
/// On a white plate regardless of theme, because a scanner reads contrast and
/// the dark-theme surface colours do not give it enough of one.
class _Qr extends StatelessWidget {
  const _Qr({required this.uri});

  final String uri;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: QrImageView(
          data: uri,
          size: 180,
          // The URI is short, and a denser code is harder to read off another screen.
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          backgroundColor: const Color(0xFFFFFFFF),
          semanticsLabel: 'QR code for your authenticator app',
        ),
      ),
    );
  }
}

/// The base32 secret, selectable and copyable for anyone typing it in.
class _SecretBlock extends StatelessWidget {
  const _SecretBlock({required this.secret, required this.onCopy});

  final String secret;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Or type this key in',
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s4),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: tokens.surfaceBase,
            border: Border.all(color: tokens.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  secret,
                  style: AppText.code.copyWith(color: tokens.textPrimary),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              AppButton(
                label: 'Copy',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
                onPressed: onCopy,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
