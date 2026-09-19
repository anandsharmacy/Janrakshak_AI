import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';

/// Email + password sign in / sign up. New accounts register as `citizen` (active immediately; the
/// handle_new_user trigger creates the profile and role). The router redirects away once a session exists.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(), _password = TextEditingController();
  final _name = TextEditingController(), _phone = TextEditingController();
  bool _signUp = false, _busy = false;
  String? _error, _info;

  @override
  void dispose() {
    for (final c in [_email, _password, _name, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = _info = null;
    });
    final auth = Supabase.instance.client.auth;
    try {
      if (_signUp) {
        final res = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {
            'requested_role': 'citizen',
            'full_name': _name.text.trim(),
            if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
          },
        );
        // With email confirmation on there is no session yet; the router redirects only once one exists.
        if (res.session == null && mounted) {
          setState(() {
            _signUp = false;
            _info = 'Account created. Check your email to confirm it, then sign in.';
          });
        }
      } else {
        await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't reach the server. Check your connection and try again.");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                ScreenHeader(
                  eyebrow: 'JanRakshak AI',
                  title: _signUp ? 'Create your account' : 'Sign in',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Report incidents and get alerts for your area.',
                  style: TextStyle(color: AppTheme.mutedOnDark),
                ),
                const SizedBox(height: 20),
                if (_signUp) ...[
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? 'Enter your name.' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    decoration: const InputDecoration(
                      labelText: 'Phone (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Enter a valid email.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: [
                    _signUp
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (v) => (v?.length ?? 0) < 8
                      ? 'Use at least 8 characters.'
                      : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (_info != null) ...[
                  const SizedBox(height: 16),
                  StatusBanner(
                    lead: 'Almost there.',
                    text: _info!,
                    color: AppColors.statusOk,
                    icon: Icons.mark_email_read_outlined,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  StatusBanner(
                    lead: 'Could not continue.',
                    text: _error!,
                    color: AppColors.statusCritical,
                    icon: Icons.error_outline,
                  ),
                ],
                const SizedBox(height: 20),
                PillButton(
                  label: _busy
                      ? 'Please wait...'
                      : (_signUp ? 'Create account' : 'Sign in'),
                  expand: true,
                  onPressed: _busy ? null : _submit,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _signUp = !_signUp;
                          _error = _info = null;
                        }),
                  child: Text(
                    _signUp
                        ? 'Have an account? Sign in'
                        : 'New here? Create an account',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
