import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../mock_data/models.dart';
import '../../mock_data/ner_state_districts.dart';
import '../../shared/ashoka_chakra.dart';
import '../../shared/widgets/form_atoms.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import 'application/auth_controller.dart';
import 'domain/auth_models.dart';

/// LoginScreen — role picker + credentials form (sign in) or registration
/// form (create account). Matches React LoginScreen / SignInView /
/// CreateAccountView exactly, now backed by Supabase Auth (the same project
/// the web dashboards use). Navigation happens automatically: the router
/// watches the auth state and redirects to the role's dashboard.
class LoginScreen extends StatefulWidget {
  final bool createMode;
  final VoidCallback onBack;

  const LoginScreen({super.key, this.createMode = false, required this.onBack});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late bool _isCreate;
  String? _banner;

  @override
  void initState() {
    super.initState();
    _isCreate = widget.createMode;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.14, 0.32, 0.54, 0.72, 0.88, 1.0],
            colors: AppColors.loginGradient,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Status bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: [
                    Text(
                      '09:41',
                      style: AppTextStyles.statusBarTime.copyWith(
                        color: AppColors.navy900,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.signal_cellular_alt,
                      size: 16,
                      color: AppColors.navy900.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.wifi,
                      size: 16,
                      color: AppColors.navy900.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.battery_full,
                      size: 16,
                      color: AppColors.navy900.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
              // Back + language row
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 16, 0),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back_ios, size: 14),
                      label: const Text('Go back'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.navy900.withValues(
                          alpha: 0.7,
                        ),
                        textStyle: AppTextStyles.buttonSmall,
                      ),
                    ),
                    const Spacer(),
                    // Language chip (static for now)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.navy900.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.language_outlined,
                            size: 14,
                            color: AppColors.navy900.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Text('English', style: AppTextStyles.captionSemibold),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Scrollable body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: Column(
                    children: [
                      if (_banner != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _Banner(
                            text: _banner!,
                            onClose: () => setState(() => _banner = null),
                          ),
                        ),
                      _isCreate
                          ? _CreateAccountView(
                              onSignIn: () => setState(() => _isCreate = false),
                              onCreated: (message) => setState(() {
                                _banner = message;
                                _isCreate = false;
                              }),
                            )
                          : _SignInView(
                              onCreateAccount: () =>
                                  setState(() => _isCreate = true),
                            ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Role data ─────────────────────────────────────────────────────────────────

class _RoleMeta {
  final AppRole role;
  final String label;
  final String desc;
  final String demoId;
  final String demoPw;
  final String placeholder;
  final IconData icon;

  const _RoleMeta({
    required this.role,
    required this.label,
    required this.desc,
    required this.demoId,
    required this.demoPw,
    required this.placeholder,
    required this.icon,
  });
}

/// Demo IDs resolve to the seeded Supabase accounts (see AuthRepository).
/// `demo1234` only works locally after running
/// `supabase/dev/local_demo_passwords.sql` — see README.
const _roles = [
  _RoleMeta(
    role: AppRole.field,
    label: 'Field Officer',
    desc: 'Ground reporting, route planning, incident logging.',
    demoId: 'NER-FO-4471',
    demoPw: 'demo1234',
    placeholder: 'field.officer@gov.in or employee ID',
    icon: Icons.alt_route_outlined,
  ),
  _RoleMeta(
    role: AppRole.district,
    label: 'District Officer',
    desc: 'District-level connectivity oversight and reporting review.',
    demoId: 'NER-DO-2210',
    demoPw: 'demo1234',
    placeholder: 'district.officer@gov.in or employee ID',
    icon: Icons.account_balance_outlined,
  ),
  _RoleMeta(
    role: AppRole.control,
    label: 'Control Room',
    desc: 'Region-wide monitoring, fleet tracking, alert broadcast.',
    demoId: 'NER-CR-0007',
    demoPw: 'demo1234',
    placeholder: 'controlroom@gov.in or employee ID',
    icon: Icons.broadcast_on_personal_outlined,
  ),
  _RoleMeta(
    role: AppRole.rider,
    label: 'Logistics Rider',
    desc: 'Assigned deliveries, route safety, live location sharing.',
    demoId: 'NER-RD-1184',
    demoPw: 'demo1234',
    placeholder: 'rider@gov.in or employee ID',
    icon: Icons.local_shipping_outlined,
  ),
];

_RoleMeta _metaFor(AppRole role) => _roles.firstWhere((r) => r.role == role);

// ── Sign In view ──────────────────────────────────────────────────────────────

class _SignInView extends ConsumerStatefulWidget {
  final VoidCallback onCreateAccount;

  const _SignInView({required this.onCreateAccount});

  @override
  ConsumerState<_SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends ConsumerState<_SignInView> {
  AppRole? _role;
  final _idCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _showPw = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  void _pickRole(_RoleMeta meta) {
    setState(() {
      _role = meta.role;
      _idCtrl.text = meta.demoId;
      _pwCtrl.text = meta.demoPw;
      _error = null;
    });
  }

  bool get _canSubmit =>
      !_busy &&
      _role != null &&
      _idCtrl.text.trim().isNotEmpty &&
      _pwCtrl.text.trim().isNotEmpty;

  Future<void> _submit() async {
    final picked = _role;
    if (picked == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = await ref
          .read(authControllerProvider.notifier)
          .signIn(officerIdOrEmail: _idCtrl.text, password: _pwCtrl.text);
      // The DB role is authoritative. Warn if the picked tile does not match —
      // the router still opens the correct dashboard for the real role.
      if (profile.role != picked && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Signed in as ${profile.role.label} (account role overrides the selection).',
            ),
          ),
        );
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign-in failed. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AshokaChakra(size: 60),
        const SizedBox(height: 12),
        Text(
          'Secure sign-in',
          style: AppTextStyles.eyebrowMd.copyWith(
            color: AppColors.navy900.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Access your workspace',
          style: AppTextStyles.heroHeading.copyWith(fontSize: 24),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),

        // Glass card
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Step 1 — role
              Row(
                children: [
                  Expanded(child: FieldLabel("Who's logging in?")),
                  Text(
                    'Step 1 of 2',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.navy900.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Select your role to continue.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.navy900.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 10),
              for (final meta in _roles)
                _RoleTile(
                  meta: meta,
                  selected: _role == meta.role,
                  onTap: _busy ? () {} : () => _pickRole(meta),
                ),

              // Step 2 — credentials
              const SizedBox(height: 16),
              Divider(color: AppColors.navy900.withValues(alpha: 0.10)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: FieldLabel('Credentials')),
                  Text(
                    'Step 2 of 2',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.navy900.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Opacity(
                opacity: _role == null ? 0.45 : 1.0,
                child: IgnorePointer(
                  ignoring: _role == null || _busy,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FieldLabel('Officer ID or email'),
                      const SizedBox(height: 6),
                      _GlassInput(
                        controller: _idCtrl,
                        placeholder: _role == null
                            ? 'Select a role first'
                            : _metaFor(_role!).placeholder,
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (_) => setState(() => _error = null),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: FieldLabel('Password')),
                          TextButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Password reset is handled by your district administrator.',
                                  ),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                            ),
                            child: Text(
                              'Forgot password?',
                              style: AppTextStyles.buttonSmall.copyWith(
                                color: AppColors.navy900.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _GlassPasswordInput(
                        controller: _pwCtrl,
                        show: _showPw,
                        onToggle: () => setState(() => _showPw = !_showPw),
                        error: _error,
                        onChanged: (_) => setState(() => _error = null),
                        onSubmitted: (_) {
                          if (_canSubmit) _submit();
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),
              // Primary CTA
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _canSubmit ? _submit : null,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _role == null
                              ? 'Log in'
                              : 'Log in as ${_metaFor(_role!).label}',
                          style: AppTextStyles.button,
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Access is provisioned by your district administrator.',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.navy900.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              // Demo note
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.deepGreen700.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.deepGreen700.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 15,
                      color: AppColors.deepGreen700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _role == null
                            ? 'Pick a role above to pre-fill demo credentials and unlock sign-in.'
                            : 'Demo credentials pre-filled for ${_metaFor(_role!).label} — tap Log in to continue.',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.navy900.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        TextButton(
          onPressed: widget.onCreateAccount,
          child: RichText(
            text: TextSpan(
              style: AppTextStyles.buttonSmall.copyWith(
                color: AppColors.navy900.withValues(alpha: 0.65),
              ),
              children: const [
                TextSpan(text: "Don't have access? "),
                TextSpan(
                  text: 'Create an account',
                  style: TextStyle(decoration: TextDecoration.underline),
                ),
              ],
            ),
          ),
        ),
        _LegalFooter(),
      ],
    );
  }
}

// ── Create Account view ───────────────────────────────────────────────────────

class _CreateAccountView extends ConsumerStatefulWidget {
  final VoidCallback onSignIn;

  /// Called after a successful sign-up that still needs email confirmation.
  final ValueChanged<String> onCreated;

  const _CreateAccountView({required this.onSignIn, required this.onCreated});

  @override
  ConsumerState<_CreateAccountView> createState() => _CreateAccountViewState();
}

class _CreateAccountViewState extends ConsumerState<_CreateAccountView> {
  AppRole? _role;
  String _name = '';
  String _cred = '';
  String _vehicle = '';
  String _phone = '';
  final _pwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showPw = false;
  bool _showConfirm = false;
  bool _busy = false;
  String? _selectedState;
  String? _selectedDistrict;
  String? _error;

  bool get _requiresLocation =>
      _role == AppRole.field || _role == AppRole.district;

  bool get _valid =>
      !_busy &&
      _name.trim().isNotEmpty &&
      _cred.trim().isNotEmpty &&
      _pwCtrl.text.length >= 8 &&
      _pwCtrl.text == _confirmCtrl.text &&
      _role != null &&
      (!_requiresLocation ||
          (_selectedState != null && _selectedDistrict != null));

  @override
  void dispose() {
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final role = _role;
    if (role == null) return;
    if (_requiresLocation &&
        (_selectedState == null || _selectedDistrict == null)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final districtValue =
          _requiresLocation ? _selectedDistrict : null;
      final sessionIssued = await ref
          .read(authControllerProvider.notifier)
          .signUp(
            officerIdOrEmail: _cred,
            password: _pwCtrl.text,
            fullName: _name,
            district: districtValue,
            state: _selectedState,
            role: role,
            vehicleRegistration: role == AppRole.rider ? _vehicle : null,
            phone: role == AppRole.rider ? _phone : null,
          );
      if (!sessionIssued && mounted) {
        widget.onCreated(
          'Account created. Check your inbox to verify your email, then sign in.',
        );
      }
      // When a session was issued the router redirects to the dashboard.
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not create the account. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AshokaChakra(size: 60),
        const SizedBox(height: 12),
        Text(
          'Create account',
          style: AppTextStyles.eyebrowMd.copyWith(
            color: AppColors.navy900.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Set up your access',
          style: AppTextStyles.heroHeading.copyWith(fontSize: 24),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        _GlassCard(
          child: Column(
            children: [
              GlassField(
                label: 'Full name',
                placeholder: 'As per official records',
                onChanged: (v) => setState(() => _name = v),
              ),
              GlassField(
                label: 'Official email',
                placeholder: 'officer@gov.in',
                keyboardType: TextInputType.emailAddress,
                onChanged: (v) => setState(() {
                  _cred = v;
                  _error = null;
                }),
              ),
              FieldLabel('Password'),
              const SizedBox(height: 6),
              _GlassPasswordInput(
                controller: _pwCtrl,
                show: _showPw,
                placeholder: 'Minimum 8 characters',
                onToggle: () => setState(() => _showPw = !_showPw),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 4),
              FieldLabel('Confirm password'),
              const SizedBox(height: 6),
              _GlassPasswordInput(
                controller: _confirmCtrl,
                show: _showConfirm,
                placeholder: 'Re-enter password',
                onToggle: () => setState(() => _showConfirm = !_showConfirm),
                error:
                    _confirmCtrl.text.isNotEmpty &&
                        _confirmCtrl.text != _pwCtrl.text
                    ? 'Passwords do not match'
                    : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              FieldLabel('Select your role'),
              const SizedBox(height: 8),
              for (final meta in _roles)
                _RoleTile(
                  meta: meta,
                  selected: _role == meta.role,
                  onTap: () => setState(() {
                    _role = meta.role;
                    if (meta.role == AppRole.control) {
                      _selectedState = null;
                      _selectedDistrict = null;
                    }
                  }),
                ),
              if (_role == AppRole.field || _role == AppRole.district) ...[
                const SizedBox(height: 8),
                GlassSelect(
                  label: 'State',
                  placeholder: 'Select State',
                  value: _selectedState,
                  options: nerStates,
                  onChanged: (v) => setState(() {
                    _selectedState = v;
                    _selectedDistrict = null;
                  }),
                ),
                GlassSelect(
                  label: 'District',
                  placeholder: _selectedState == null
                      ? 'Select State first'
                      : 'Select District',
                  value: _selectedDistrict,
                  options: _selectedState != null
                      ? (nerStateDistricts[_selectedState!] ?? [])
                      : [],
                  enabled: _selectedState != null,
                  onChanged: (v) => setState(() => _selectedDistrict = v),
                ),
              ],
              if (_role == AppRole.rider)
                Column(
                  children: [
                    GlassField(
                      label: 'Mobile number',
                      placeholder: 'For delivery and safety updates',
                      keyboardType: TextInputType.phone,
                      onChanged: (v) => setState(() => _phone = v),
                    ),
                    GlassField(
                      label: 'Vehicle registration (optional)',
                      placeholder: 'e.g. ML-05-A-2047',
                      onChanged: (v) => setState(() => _vehicle = v),
                    ),
                  ],
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_outlined,
                        size: 14,
                        color: AppColors.signalRed700,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.signalRed700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _valid ? _submit : null,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Create Account'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your account is activated with the selected role as soon as it is created. Roles are verified by your district administrator.',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.navy900.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: widget.onSignIn,
          child: RichText(
            text: TextSpan(
              style: AppTextStyles.buttonSmall.copyWith(
                color: AppColors.navy900.withValues(alpha: 0.65),
              ),
              children: const [
                TextSpan(text: 'Already have access? '),
                TextSpan(
                  text: 'Sign in',
                  style: TextStyle(decoration: TextDecoration.underline),
                ),
              ],
            ),
          ),
        ),
        _LegalFooter(),
      ],
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  final String text;
  final VoidCallback onClose;
  const _Banner({required this.text, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.deepGreen700.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.deepGreen700.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.mark_email_read_outlined,
            size: 16,
            color: AppColors.deepGreen700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.caption.copyWith(color: AppColors.navy900),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: AppColors.navy900.withValues(alpha: 0.6),
            onPressed: onClose,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.83),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.68)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy900.withValues(alpha: 0.10),
            blurRadius: 40,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: AppColors.navy900.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _RoleTile extends StatelessWidget {
  final _RoleMeta meta;
  final bool selected;
  final VoidCallback onTap;

  const _RoleTile({
    required this.meta,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.navy900.withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppColors.navy900.withValues(alpha: 0.40)
                : AppColors.navy900.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.navy900
                    : Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected
                      ? AppColors.navy900.withValues(alpha: 0.3)
                      : AppColors.navy900.withValues(alpha: 0.15),
                ),
              ),
              child: Icon(
                meta.icon,
                size: 18,
                color: selected
                    ? Colors.white
                    : AppColors.navy900.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(meta.label, style: AppTextStyles.cardTitle),
                  Text(
                    meta.desc,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.navy900.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: selected ? AppColors.navy900 : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? AppColors.navy900
                      : AppColors.navy900.withValues(alpha: 0.25),
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassInput extends StatelessWidget {
  final TextEditingController controller;
  final String? placeholder;
  final TextInputType keyboardType;
  final ValueChanged<String>? onChanged;

  const _GlassInput({
    required this.controller,
    this.placeholder,
    this.keyboardType = TextInputType.text,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      autocorrect: false,
      style: AppTextStyles.inputText,
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: AppTextStyles.inputHint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: AppColors.navy900.withValues(alpha: 0.15),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: AppColors.navy900.withValues(alpha: 0.15),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: AppColors.navy900.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }
}

class _GlassPasswordInput extends StatelessWidget {
  final TextEditingController controller;
  final bool show;
  final VoidCallback onToggle;
  final String? error;
  final String? placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const _GlassPasswordInput({
    required this.controller,
    required this.show,
    required this.onToggle,
    this.error,
    this.placeholder,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = error != null && error!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasError
                  ? AppColors.signalRed700
                  : AppColors.navy900.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: !show,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  style: AppTextStyles.inputText,
                  decoration: InputDecoration(
                    hintText: placeholder,
                    hintStyle: AppTextStyles.inputHint,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: onToggle,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: Size.zero,
                ),
                child: Text(
                  show ? 'Hide' : 'Show',
                  style: AppTextStyles.captionSemibold.copyWith(
                    color: AppColors.navy900.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_outlined,
                  size: 13,
                  color: AppColors.signalRed700,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    error!,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.signalRed700,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LegalFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      child: Text(
        'For official use only. Activity on this system is monitored and logged. Unauthorized access is an offence under applicable law.',
        style: AppTextStyles.disclaimer,
        textAlign: TextAlign.center,
      ),
    );
  }
}
