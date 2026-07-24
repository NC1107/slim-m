// SPDX-License-Identifier: Apache-2.0
/// Connecting to a server and signing in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import '../providers/sync_controller.dart';

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
  final _server = TextEditingController(text: 'http://10.0.0.100:8095');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();

  bool _creatingAccount = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
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
      await ref.read(syncControllerProvider.notifier).start();
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
                ),
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
