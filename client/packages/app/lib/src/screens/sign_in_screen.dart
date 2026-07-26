// SPDX-License-Identifier: Apache-2.0
/// Connecting to a server and signing in.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import '../providers/push_controller.dart';

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
  // Prefilled from the server chosen during onboarding, which every entry
  // path has already written; a hardcoded default here silently overrode
  // that choice on submit.
  late final TextEditingController _server = TextEditingController(
    text: ref.read(serverUrlProvider).toString(),
  );
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();

  bool _creatingAccount = false;
  bool _busy = false;
  String? _error;

  /// Whether the server in the field can deliver push, from its /version:
  /// true, false, or null while unknown (probe pending, unreachable, or a
  /// server too old to say). Only an explicit false renders the notice,
  /// because warning someone off a server that has push is worse than
  /// staying quiet.
  bool? _pushEnabled;
  Timer? _probeDebounce;

  @override
  void initState() {
    super.initState();
    _probePush();
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
    return Uri(
      scheme: parsed.scheme,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
    );
  }

  /// Asks the server in the field whether it can deliver push at all, so
  /// someone joining a LAN-only deployment learns their phone will stay
  /// silent while they are still choosing, not after a week of wondering.
  Future<void> _probePush() async {
    final target = _probeTarget(_server.text);
    if (target == null) {
      setState(() => _pushEnabled = null);
      return;
    }
    final client = ref.read(probeApiProvider)(target);
    bool? answer;
    try {
      answer = (await client.version()).pushEnabled;
    } on ApiException {
      // Unreachable or refusing means unknown, and sign-in itself will say
      // "could not reach that server" with more authority than a probe.
      answer = null;
    } catch (_) {
      // A host that answers 200 with something that is not a slim-m
      // /version body is just as unknown as one that refuses to connect. A
      // foreign or hostile server must not crash sign-in with a shaped
      // reply, so this deliberately catches everything the parse can throw.
      answer = null;
    } finally {
      client.close();
    }
    if (!mounted) return;
    // Guarded on every path, failures included: a slow answer about a
    // previously typed address must not relabel the current one, whether
    // it would set the notice or clear it.
    if (_probeTarget(_server.text) == target) {
      setState(() => _pushEnabled = answer);
    }
  }

  void _onServerEdited(String _) {
    // The old answer is about the old address the moment the field changes.
    if (_pushEnabled != null) setState(() => _pushEnabled = null);
    _probeDebounce?.cancel();
    _probeDebounce = Timer(const Duration(milliseconds: 600), _probePush);
  }

  Future<void> _submit() async {
    final address = Uri.tryParse(_server.text.trim());
    if (address == null || !address.hasScheme || address.host.isEmpty) {
      setState(() => _error = 'That does not look like a server address.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    ref.read(serverUrlProvider.notifier).state = address;
    final api = ref.read(apiProvider);

    try {
      if (_creatingAccount) {
        await api.register(
          username: _username.text.trim(),
          displayName: _displayName.text.trim().isEmpty
              ? _username.text.trim()
              : _displayName.text.trim(),
          password: _password.text,
          deviceName: 'desktop',
        );
      } else {
        await api.login(
          username: _username.text.trim(),
          password: _password.text,
          deviceName: 'desktop',
        );
      }
      // Redeem the invite that brought them here, now that an account exists.
      final invite = ref.read(pendingInviteProvider);
      if (invite != null) {
        try {
          await api.redeemInvite(invite);
        } on ApiException {
          // The account is real either way; a spent code should not strand
          // someone on the sign-in screen with no way forward.
        }
        ref.read(pendingInviteProvider.notifier).state = null;
      }
      // Sync is not started here: SyncController is session-driven (see its
      // class doc) and its own listener already reacts to the session.set()
      // that api.register()/api.login() just performed. Starting it again
      // explicitly raced that listener's own start() and opened a second
      // socket that went on to kick the first, healthy one offline.
      //
      // Fire-and-forget: a denied permission or unreachable server here must
      // never hold up sign-in, which is already complete at this point.
      unawaited(ref.read(pushControllerProvider.notifier).register());
    } on ApiException catch (e) {
      // Say what actually happened. "Something went wrong" tells the user
      // nothing about whether to fix their password or wait.
      setState(() => _error = switch (e) {
            UnauthorizedException() =>
              'That username and password did not match.',
            ConflictException() => 'That username is already taken.',
            BadRequestException(:final message) => message,
            RateLimitedException() =>
              'Too many attempts just now. Wait a moment and try again.',
            UnavailableException() => 'The server is busy. Try again shortly.',
            TransportException() =>
              'Could not reach that server. Check the address and your connection.',
            _ => 'The server refused that. ${e.message}',
          });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'slim-m',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  _creatingAccount ? 'Create an account' : 'Sign in',
                  style: TextStyle(color: tokens.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.s24),
                TextField(
                  controller: _server,
                  decoration: const InputDecoration(
                    labelText: 'Server',
                    helperText: 'The address of the server you are joining.',
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onChanged: _onServerEdited,
                ),
                if (_pushEnabled == false) ...[
                  const SizedBox(height: AppSpacing.s8),
                  Semantics(
                    liveRegion: true,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          AppIcons.notificationsOff,
                          size: 16,
                          color: tokens.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        Expanded(
                          child: Text(
                            'This server cannot send push notifications. '
                            'You can still use it, but phones will only see '
                            'new messages while the app is open.',
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.s16),
                TextField(
                  controller: _username,
                  decoration: const InputDecoration(labelText: 'Username'),
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
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _busy ? null : _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.s16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
