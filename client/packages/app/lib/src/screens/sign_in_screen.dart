// SPDX-License-Identifier: Apache-2.0
/// Connecting to a server and signing in.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

import '../api_failure.dart';
import '../providers/providers.dart';
import '../providers/push_controller.dart';
import '../routing/routes.dart';
import '../server_address_reduction.dart';
import '../server_scheme_policy.dart';
import '../widgets/onboarding_shell.dart';
import '../widgets/server_identity_confirmation.dart';
import '../widgets/server_notice.dart';

/// Sign in or create an account on a chosen server.
///
/// The server address is part of this screen rather than buried in settings,
/// because self-hosting is the normal case: which server you are on is a
/// first-class choice, not an advanced option.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  /// Prefilled from the server chosen during onboarding, which every entry path
  /// has already written; a hardcoded default here silently overrode that
  /// choice on submit.
  late final TextEditingController _server = TextEditingController(
    text: ref.read(serverUrlProvider).toString(),
  );
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();

  bool _creatingAccount = false;
  bool _busy = false;

  /// The current failure and the field it belongs to (error grammar 03: an
  /// error lands on the thing that failed, with its content preserved).
  /// [_ErrorField.form] is the fallback for failures no one field owns.
  (_ErrorField, String)? _error;

  String? _errorFor(_ErrorField field) =>
      _error?.$1 == field ? _error!.$2 : null;

  /// What the server in the field said about itself, or null while nothing is
  /// known: the probe is pending, the host is unreachable, or it answered with
  /// something that is not a slim-m `/version`. Every notice below reads from
  /// this, and null renders none of them, because warning someone off a server
  /// that is merely slow to answer is worse than staying quiet.
  Version? _probed;
  Timer? _probeDebounce;

  /// How [_probed]'s identity compares against whatever this app already
  /// pinned for the address in the field. Read alongside [_probed] so the
  /// chip never has to guess a status for an answer it has not seen yet.
  ServerIdentityStatus? _identityStatus;

  @override
  void initState() {
    super.initState();
    // Somebody arriving with an invite code has no account here yet, so the
    // screen opens on creating one rather than asserting "Sign in" at the one
    // person it cannot apply to. The toggle still offers the other mode.
    _creatingAccount = ref.read(pendingInviteProvider) != null;
    _probeServer();
  }

  @override
  void dispose() {
    _probeDebounce?.cancel();
    _server.dispose();
    _username.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  /// Reduces a typed address to the scheme, host, and port worth probing.
  /// Anything else it carries (path, query, userinfo) must not ride along
  /// on a request that fires as someone types: pasted userinfo would even
  /// become a Basic auth header sent to whatever host is in the field.
  Uri? _probeTarget(String text) {
    final parsed = Uri.tryParse(text.trim());
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return null;
    }
    return reduceServerAddress(parsed);
  }

  /// How [identity] compares against whatever is pinned for [target], for
  /// the passive chip only: read-only, no pinning and no navigation. The
  /// active check that pins and can block a connection lives in [_submit],
  /// via [confirmServerIdentity].
  Future<ServerIdentityStatus> _identityStatusFor(
    Uri target,
    ServerIdentity? identity,
  ) async {
    if (identity == null) return ServerIdentityStatus.unknown;
    final pinned = await ref
        .read(keyStoreProvider)
        .read(identityHandleFor(target));
    if (pinned == null) return ServerIdentityStatus.unknown;
    return pinned == identity.publicKey
        ? ServerIdentityStatus.confirmed
        : ServerIdentityStatus.mismatch;
  }

  /// Asks the server in the field what it is, so the facts worth knowing
  /// before joining are on screen while the choice is still open: whether it
  /// can deliver push at all, whether joining needs an invite, and whether it
  /// offers reporting and blocking.
  ///
  /// Every failure resolves to "unknown". A host that answers 200 with
  /// something that is not a slim-m `/version` body is as unknown as one that
  /// refuses to connect, so the bare `catch` is deliberate: a foreign or
  /// hostile server must not crash sign-in with a shaped reply.
  ///
  /// The result is applied only if the field still holds the address that was
  /// probed, on every path including failures, so a slow answer about a
  /// previously typed address cannot relabel the current one either way.
  Future<void> _probeServer() async {
    final target = _probeTarget(_server.text);
    if (target == null) {
      setState(() {
        _probed = null;
        _identityStatus = null;
      });
      return;
    }
    final client = ref.read(probeApiProvider)(target);
    Version? answer;
    try {
      answer = await client.version();
    } on ApiException {
      // Unreachable or refusing means unknown, and sign-in itself will say
      // "could not reach that server" with more authority than a probe.
      answer = null;
    } catch (_) {
      // A shaped reply from a foreign host is as unknown as a refusal.
      answer = null;
    } finally {
      client.close();
    }
    final status = await _identityStatusFor(target, answer?.identity);
    if (!mounted) return;
    if (_probeTarget(_server.text) == target) {
      setState(() {
        _probed = answer;
        _identityStatus = status;
      });
    }
  }

  void _onServerEdited(String _) {
    // The old answer is about the old address the moment the field changes.
    if (_probed != null) {
      setState(() {
        _probed = null;
        _identityStatus = null;
      });
    }
    _probeDebounce?.cancel();
    _probeDebounce = Timer(const Duration(milliseconds: 600), _probeServer);
  }

  /// Signs in or registers, then starts push.
  ///
  /// On registration the invite code goes in with the signup rather than being
  /// redeemed after it: a claimed deployment refuses an uninvited registration
  /// outright, so there is no account to redeem against until that call
  /// succeeds.
  ///
  /// Sync is deliberately not started here. `SyncController` is session-driven
  /// (see its class doc) and its own listener already reacts to the
  /// `session.set()` that register or login just performed. Starting it again
  /// explicitly raced that listener and opened a second socket, which went on
  /// to kick the first, healthy one offline.
  ///
  /// Push registration is fire-and-forget: a denied permission or unreachable
  /// server must never hold up a sign-in that is already complete.
  ///
  /// The address is reduced and its identity confirmed before anything is
  /// persisted or sent: this is "connecting", in the sense
  /// [confirmServerIdentity] means it, and binding the check here (rather
  /// than to the field being typed) is what makes a returning sign-in - not
  /// only the manual onboarding dialog - a place TOFU's comparison runs.
  Future<void> _submit() async {
    final address = Uri.tryParse(_server.text.trim());
    if (address == null || !address.hasScheme || address.host.isEmpty) {
      setState(
        () => _error = (
          _ErrorField.server,
          'That does not look like a server address.',
        ),
      );
      return;
    }

    if (requireSecureScheme(address) case final schemeError?) {
      setState(() => _error = (_ErrorField.server, schemeError));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final reduced = reduceServerAddress(address);
    if (!await confirmServerIdentity(context, ref, reduced)) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;

    ref.read(chosenServerProvider.notifier).choose(reduced);
    final api = ref.read(apiProvider);

    final invite = ref.read(pendingInviteProvider);
    try {
      if (_creatingAccount) {
        await api.register(
          username: _username.text.trim(),
          displayName: _displayName.text.trim().isEmpty
              ? _username.text.trim()
              : _displayName.text.trim(),
          password: _password.text,
          deviceName: deviceDisplayName,
          inviteCode: invite,
        );
      } else {
        await api.login(
          username: _username.text.trim(),
          password: _password.text,
          deviceName: deviceDisplayName,
        );
        // An existing account can still spend a code, for the role it grants.
        if (invite != null) {
          try {
            await api.redeemInvite(invite);
          } on ApiException {
            // The session is real either way; a spent code should not strand
            // someone on the sign-in screen with no way forward.
          }
        }
      }
      if (invite != null) {
        ref.read(pendingInviteProvider.notifier).state = null;
      }
      unawaited(ref.read(pushControllerProvider.notifier).register());
    } on ApiException catch (e) {
      // Say what actually happened. "Something went wrong" tells the user
      // nothing about whether to fix their password or wait.
      setState(
        () => _error = switch (e) {
          UnauthorizedException() => (
            _ErrorField.password,
            'Wrong username or password.',
          ),
          ConflictException() => (
            _ErrorField.username,
            'That username is already taken.',
          ),
          BadRequestException(:final message) => (
            _ErrorField.form,
            sentenceCase(message),
          ),
          RateLimitedException() => (
            _ErrorField.form,
            'Too many attempts just now. Wait a moment and try again.',
          ),
          UnavailableException() => (
            _ErrorField.form,
            'The server is busy. Try again shortly.',
          ),
          TransportException() => (
            _ErrorField.server,
            "This Space didn't answer. It may be restarting, or the "
                'address may be wrong. Nothing was sent.',
          ),
          _ => (
            _ErrorField.form,
            'The server refused that. ${sentenceCase(e.message)}',
          ),
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return OnboardingShell(
      // Creating an account is the last of the join steps; signing back in to
      // a server you already trust is one act and gets no stepper.
      step: _creatingAccount ? OnboardingStep.identity : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _creatingAccount ? 'Create an account' : 'Welcome back',
            style: AppText.title.copyWith(
              color: tokens.textPrimary,
              fontWeight: AppWeights.semi,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          // Only once it has answered; a typed address says nothing yet.
          if (_probed case final version?)
            ServerIdentityChip(
              spaceName: version.name,
              host: Uri.tryParse(_server.text)?.host ?? _server.text,
              status: _identityStatus ?? ServerIdentityStatus.unknown,
            ),
          const SizedBox(height: AppSpacing.s8),
          TextField(
            controller: _server,
            decoration: InputDecoration(
              labelText: 'Server',
              helperText: "The Space you're joining - its server address.",
              errorText: _errorFor(_ErrorField.server),
              errorMaxLines: 3,
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: _onServerEdited,
          ),
          // First of the three: the other two are about convenience,
          // this one is about whether you have any recourse here.
          if (_probed case final version?) ServerSafetyNotice(version: version),
          // Only while creating an account: it is not a fact a
          // returning member has any use for.
          if (_creatingAccount && _probed?.inviteRequired == true)
            const ServerNotice(
              icon: AppIcons.invite,
              message:
                  'This Space is invite only. Ask a member for a '
                  'code, then use "Join a different Space" below '
                  'to redeem it. An admin can open joining to '
                  'anyone in Settings, under Space.',
            ),
          if (_probed?.pushEnabled == false)
            const ServerNotice(
              icon: AppIcons.notificationsOff,
              message:
                  'This Space cannot send push notifications. '
                  'You can still use it, but phones will only see '
                  'new messages while the app is open.',
            ),
          const SizedBox(height: AppSpacing.s16),
          TextField(
            controller: _username,
            decoration: InputDecoration(
              labelText: 'Username',
              errorText: _errorFor(_ErrorField.username),
            ),
            autocorrect: false,
            autofillHints: const [AutofillHints.username],
          ),
          if (_creatingAccount) ...[
            const SizedBox(height: AppSpacing.s16),
            TextField(
              controller: _displayName,
              decoration: const InputDecoration(
                labelText: 'Display name',
                helperText: 'What others see. Defaults to your username.',
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s16),
          TextField(
            controller: _password,
            decoration: InputDecoration(
              labelText: 'Password',
              errorText: _errorFor(_ErrorField.password),
            ),
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _busy ? null : _submit(),
          ),
          if (_errorFor(_ErrorField.form) case final formError?) ...[
            const SizedBox(height: AppSpacing.s16),
            Semantics(
              liveRegion: true,
              child: Text(
                formError,
                style: TextStyle(color: tokens.dangerText),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_creatingAccount ? 'Create account' : 'Sign in'),
          ),
          const SizedBox(height: AppSpacing.s8),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _creatingAccount = !_creatingAccount;
                    _error = null;
                  }),
            child: Text(
              _creatingAccount
                  ? 'I already have an account'
                  : 'Create an account instead',
            ),
          ),
          // Once a Space is remembered, sign-in is where a signed-out
          // user lands, so this is the only way back to invite redemption.
          TextButton(
            onPressed: _busy ? null : () => context.go(Routes.onboarding),
            child: const Text('Join a different Space'),
          ),
        ],
      ),
    );
  }
}

/// Which part of the form a failure belongs to.
enum _ErrorField { server, username, password, form }
