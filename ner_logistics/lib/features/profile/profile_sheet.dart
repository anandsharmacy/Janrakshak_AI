import 'package:flutter/material.dart';
import '../../mock_data/models.dart';
import '../../mock_data/mock_officers.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import '../../shared/widgets/ner_toggle.dart';

/// ProfileSheet — slides up from the bottom over any screen.
/// Two tabs: Profile (read-only info) + Settings (5 accordion sections).
/// Matches React ProfileScreen exactly — same sections, same field order.
class ProfileSheet extends StatefulWidget {
  final AppRole role;
  final VoidCallback onClose;
  final VoidCallback onSignOut;

  /// Real account data from Supabase; falls back to the demo officer for the
  /// role when not signed in (e.g. widget tests).
  final Officer? officer;

  const ProfileSheet({
    super.key,
    required this.role,
    required this.onClose,
    required this.onSignOut,
    this.officer,
  });

  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // ── Settings accordion state ──────────────────────────────────────
  String? _openSection; // 'edit' | 'notifications' | 'theme' | 'language' | 'security'

  // Edit profile
  late String _editName;
  late String _editPhone;
  late String _editEmail;
  bool _avatarUploaded = false;

  // Notifications
  bool _notifCritical = true;
  bool _notifIncidents = true;
  bool _notifTasks = true;
  bool _notifAi = false;
  bool _notifEmail = true;
  bool _notifSms = false;
  bool _notifDigest = false;

  // Theme
  String _theme = 'light'; // 'light' | 'dark' | 'system'

  // Language
  String _language = 'en';

  // Security
  bool _twoFa = true;

  // Save states
  String _editSave = 'idle'; // idle | saving | saved
  String _notifSave = 'idle';
  String _langSave = 'idle';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    final o = _officer;
    _editName = o.name;
    _editPhone = o.phone;
    _editEmail = o.email;
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Officer get _officer {
    final real = widget.officer;
    if (real != null) return real;
    switch (widget.role) {
      case AppRole.field:   return fieldOfficer;
      case AppRole.district: return districtOfficer;
      case AppRole.control: return controlOfficer;
      case AppRole.rider: return riderOfficer;
    }
  }

  void _toggleSection(String key) =>
      setState(() => _openSection = _openSection == key ? null : key);

  Future<void> _simulateSave(String field) async {
    setState(() {
      if (field == 'edit') _editSave = 'saving';
      if (field == 'notif') _notifSave = 'saving';
      if (field == 'lang') _langSave = 'saving';
    });
    await Future.delayed(const Duration(milliseconds: 900));
    setState(() {
      if (field == 'edit') _editSave = 'saved';
      if (field == 'notif') _notifSave = 'saved';
      if (field == 'lang') _langSave = 'saved';
    });
    await Future.delayed(const Duration(milliseconds: 2500));
    if (mounted) {
      setState(() {
        if (field == 'edit') _editSave = 'idle';
        if (field == 'notif') _notifSave = 'idle';
        if (field == 'lang') _langSave = 'idle';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _officer;
    return GestureDetector(
      onTap: widget.onClose,
      child: ColoredBox(
        color: Colors.black.withOpacity(0.50),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.95,
              ),
              decoration: const BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC4C8CD),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Navy profile header
                  _ProfileHeader(
                    officer: o,
                    avatarUploaded: _avatarUploaded,
                    onClose: widget.onClose,
                    onCameraToggle: () =>
                        setState(() => _avatarUploaded = !_avatarUploaded),
                  ),
                  // Account status bar
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                          bottom: BorderSide(color: AppColors.hairline)),
                    ),
                    child: Row(
                      children: [
                        Text('Account Status',
                            style: AppTextStyles.caption),
                        const Spacer(),
                        Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: AppColors.deepGreen700,
                                shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text('Active · Verified',
                            style: AppTextStyles.captionSemibold.copyWith(
                                color: AppColors.deepGreen700)),
                      ],
                    ),
                  ),
                  // Tab bar
                  Container(
                    color: Colors.white,
                    child: TabBar(
                      controller: _tab,
                      tabs: const [Tab(text: 'Profile'), Tab(text: 'Settings')],
                    ),
                  ),
                  // Tab content
                  Flexible(
                    child: TabBarView(
                      controller: _tab,
                      children: [
                        _ProfileTab(
                          officer: o,
                          onEditTap: () {
                            _tab.animateTo(1);
                            _toggleSection('edit');
                          },
                        ),
                        _SettingsTab(
                          openSection: _openSection,
                          onToggle: _toggleSection,
                          // Edit
                          editName: _editName,
                          editPhone: _editPhone,
                          editEmail: _editEmail,
                          avatarUploaded: _avatarUploaded,
                          editSave: _editSave,
                          onEditName: (v) => setState(() => _editName = v),
                          onEditPhone: (v) => setState(() => _editPhone = v),
                          onEditEmail: (v) => setState(() => _editEmail = v),
                          onAvatarToggle: () => setState(
                              () => _avatarUploaded = !_avatarUploaded),
                          onSaveProfile: () => _simulateSave('edit'),
                          // Notifications
                          notifCritical: _notifCritical,
                          notifIncidents: _notifIncidents,
                          notifTasks: _notifTasks,
                          notifAi: _notifAi,
                          notifEmail: _notifEmail,
                          notifSms: _notifSms,
                          notifDigest: _notifDigest,
                          notifSave: _notifSave,
                          onToggleNotif: (key) => setState(() {
                            switch (key) {
                              case 'critical': _notifCritical = !_notifCritical; break;
                              case 'incidents': _notifIncidents = !_notifIncidents; break;
                              case 'tasks': _notifTasks = !_notifTasks; break;
                              case 'ai': _notifAi = !_notifAi; break;
                              case 'email': _notifEmail = !_notifEmail; break;
                              case 'sms': _notifSms = !_notifSms; break;
                              case 'digest': _notifDigest = !_notifDigest; break;
                            }
                          }),
                          onSaveNotif: () => _simulateSave('notif'),
                          // Theme
                          theme: _theme,
                          onTheme: (v) => setState(() => _theme = v),
                          // Language
                          language: _language,
                          langSave: _langSave,
                          onLanguage: (v) => setState(() => _language = v),
                          onApplyLanguage: () => _simulateSave('lang'),
                          // Security
                          twoFa: _twoFa,
                          onTwoFa: (v) => setState(() => _twoFa = v),
                          // Sign out
                          onSignOut: widget.onSignOut,
                        ),
                      ],
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
}

// ── Profile header (navy bg) ─────────────────────────────────────────────────
class _ProfileHeader extends StatelessWidget {
  final Officer officer;
  final bool avatarUploaded;
  final VoidCallback onClose;
  final VoidCallback onCameraToggle;

  const _ProfileHeader({
    required this.officer,
    required this.avatarUploaded,
    required this.onClose,
    required this.onCameraToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy900,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
      child: Row(
        children: [
          // Avatar with camera overlay
          Stack(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: avatarUploaded
                      ? AppColors.gold
                      : Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withOpacity(0.2), width: 2),
                ),
                alignment: Alignment.center,
                child: avatarUploaded
                    ? Text(officer.initials,
                        style: AppTextStyles.statValue.copyWith(
                            color: AppColors.navy900, fontSize: 22))
                    : const Icon(Icons.person_outline,
                        size: 28, color: Colors.white),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: onCameraToggle,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.camera_alt_outlined,
                        size: 12, color: AppColors.navy900),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(officer.name,
                    style: AppTextStyles.sectionHeading.copyWith(
                        color: Colors.white,
                        fontSize: 18),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(officer.officerId,
                    style: AppTextStyles.caption.copyWith(
                        color: Colors.white70)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.gold.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: AppColors.gold,
                              shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text(officer.roleLabel,
                          style: AppTextStyles.eyebrow.copyWith(
                              color: AppColors.gold, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 18),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

// ── Profile tab ───────────────────────────────────────────────────────────────
class _ProfileTab extends StatelessWidget {
  final Officer officer;
  final VoidCallback onEditTap;

  const _ProfileTab({required this.officer, required this.onEditTap});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(label: 'Officer Information'),
          _InfoTable(rows: [
            _InfoRow('Full Name', officer.name),
            _InfoRow('Officer ID', officer.officerId),
            _InfoRow('Role', officer.roleLabel),
            _InfoRow('Department', officer.department),
            _InfoRow('District / Region', officer.region),
          ]),
          _SectionHeader(label: 'Contact Details'),
          _InfoTable(rows: [
            _InfoRow('Phone', officer.phone),
            _InfoRow('Email', officer.email),
          ]),
          _SectionHeader(label: 'Session'),
          _InfoTable(rows: [
            _InfoRow('Last Login', officer.lastLogin),
            _InfoRow('Connectivity', '4G Online'),
          ]),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onEditTap,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit Profile'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTable extends StatelessWidget {
  final List<_InfoRow> rows;
  const _InfoTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: rows
            .asMap()
            .entries
            .map((e) => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: e.key < rows.length - 1
                        ? Border(
                            bottom: BorderSide(color: AppColors.hairline))
                        : null,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(e.value.label,
                            style: AppTextStyles.bodySmall),
                      ),
                      Expanded(
                        child: Text(e.value.value,
                            style: AppTextStyles.bodySmallMedium
                                .copyWith(textBaseline: TextBaseline.alphabetic),
                            textAlign: TextAlign.right),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _InfoRow {
  final String label, value;
  const _InfoRow(this.label, this.value);
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8, left: 4),
        child: Text(
          label.toUpperCase(),
          style: AppTextStyles.eyebrow.copyWith(
              color: AppColors.slate500.withOpacity(0.5)),
        ),
      );
}

// ── Settings tab ──────────────────────────────────────────────────────────────
class _SettingsTab extends StatelessWidget {
  final String? openSection;
  final ValueChanged<String> onToggle;

  // Edit
  final String editName, editPhone, editEmail;
  final bool avatarUploaded;
  final String editSave;
  final ValueChanged<String> onEditName, onEditPhone, onEditEmail;
  final VoidCallback onAvatarToggle, onSaveProfile;

  // Notifications
  final bool notifCritical, notifIncidents, notifTasks, notifAi,
      notifEmail, notifSms, notifDigest;
  final String notifSave;
  final ValueChanged<String> onToggleNotif;
  final VoidCallback onSaveNotif;

  // Theme
  final String theme;
  final ValueChanged<String> onTheme;

  // Language
  final String language, langSave;
  final ValueChanged<String> onLanguage;
  final VoidCallback onApplyLanguage;

  // Security
  final bool twoFa;
  final ValueChanged<bool> onTwoFa;

  final VoidCallback onSignOut;

  const _SettingsTab({
    required this.openSection,
    required this.onToggle,
    required this.editName,
    required this.editPhone,
    required this.editEmail,
    required this.avatarUploaded,
    required this.editSave,
    required this.onEditName,
    required this.onEditPhone,
    required this.onEditEmail,
    required this.onAvatarToggle,
    required this.onSaveProfile,
    required this.notifCritical,
    required this.notifIncidents,
    required this.notifTasks,
    required this.notifAi,
    required this.notifEmail,
    required this.notifSms,
    required this.notifDigest,
    required this.notifSave,
    required this.onToggleNotif,
    required this.onSaveNotif,
    required this.theme,
    required this.onTheme,
    required this.language,
    required this.langSave,
    required this.onLanguage,
    required this.onApplyLanguage,
    required this.twoFa,
    required this.onTwoFa,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      child: Column(
        children: [
          // 1 · Edit Profile
          _AccordionSection(
            icon: Icons.edit_outlined,
            label: 'Edit Profile',
            isOpen: openSection == 'edit',
            onToggle: () => onToggle('edit'),
            child: _EditProfileBody(
              name: editName,
              phone: editPhone,
              email: editEmail,
              saveState: editSave,
              onName: onEditName,
              onPhone: onEditPhone,
              onEmail: onEditEmail,
              onSave: onSaveProfile,
            ),
          ),
          const SizedBox(height: 10),
          // 2 · Notifications
          _AccordionSection(
            icon: Icons.notifications_outlined,
            label: 'Notifications',
            isOpen: openSection == 'notifications',
            onToggle: () => onToggle('notifications'),
            child: _NotificationsBody(
              critical: notifCritical,
              incidents: notifIncidents,
              tasks: notifTasks,
              ai: notifAi,
              email: notifEmail,
              sms: notifSms,
              digest: notifDigest,
              saveState: notifSave,
              onToggle: onToggleNotif,
              onSave: onSaveNotif,
            ),
          ),
          const SizedBox(height: 10),
          // 3 · Theme
          _AccordionSection(
            icon: Icons.wb_sunny_outlined,
            label: 'Theme & Appearance',
            isOpen: openSection == 'theme',
            onToggle: () => onToggle('theme'),
            child: _ThemeBody(theme: theme, onTheme: onTheme),
          ),
          const SizedBox(height: 10),
          // 4 · Language
          _AccordionSection(
            icon: Icons.language_outlined,
            label: 'Language',
            isOpen: openSection == 'language',
            onToggle: () => onToggle('language'),
            child: _LanguageBody(
              language: language,
              saveState: langSave,
              onLanguage: onLanguage,
              onApply: onApplyLanguage,
            ),
          ),
          const SizedBox(height: 10),
          // 5 · Security
          _AccordionSection(
            icon: Icons.shield_outlined,
            label: 'Security & Password',
            isOpen: openSection == 'security',
            onToggle: () => onToggle('security'),
            child: _SecurityBody(twoFa: twoFa, onTwoFa: onTwoFa),
          ),
          const SizedBox(height: 24),
          // Sign out
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout_outlined, size: 16),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.signalRed700,
                side: BorderSide(
                    color: AppColors.signalRed700.withOpacity(0.4)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Accordion section wrapper ────────────────────────────────────────────────
class _AccordionSection extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isOpen;
  final VoidCallback onToggle;
  final Widget child;

  const _AccordionSection({
    required this.icon,
    required this.label,
    required this.isOpen,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: isOpen
                ? const BorderRadius.vertical(top: Radius.circular(6))
                : BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isOpen
                          ? AppColors.navy900
                          : AppColors.paper,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon,
                        size: 17,
                        color: isOpen
                            ? Colors.white
                            : AppColors.navy900.withOpacity(0.7)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label,
                        style: AppTextStyles.cardTitle),
                  ),
                  AnimatedRotation(
                    turns: isOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down,
                        size: 20,
                        color: AppColors.slate500.withOpacity(0.5)),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            child: isOpen
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    decoration: BoxDecoration(
                      border: Border(
                          top: BorderSide(color: AppColors.hairline)),
                    ),
                    child: child,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ── Edit Profile body ────────────────────────────────────────────────────────
class _EditProfileBody extends StatelessWidget {
  final String name, phone, email, saveState;
  final ValueChanged<String> onName, onPhone, onEmail;
  final VoidCallback onSave;

  const _EditProfileBody({
    required this.name, required this.phone, required this.email,
    required this.saveState,
    required this.onName, required this.onPhone, required this.onEmail,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        _SettingsField(label: 'Full Name', value: name, onChanged: onName),
        _SettingsField(label: 'Phone', value: phone, onChanged: onPhone,
            keyboardType: TextInputType.phone),
        _SettingsField(label: 'Email', value: email, onChanged: onEmail,
            keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: saveState == 'saving' ? null : onSave,
            child: saveState == 'saving'
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(saveState == 'saved'
                    ? '✓ Profile updated' : 'Save Changes'),
          ),
        ),
      ],
    );
  }
}

// ── Notifications body ───────────────────────────────────────────────────────
class _NotificationsBody extends StatelessWidget {
  final bool critical, incidents, tasks, ai, email, sms, digest;
  final String saveState;
  final ValueChanged<String> onToggle;
  final VoidCallback onSave;

  const _NotificationsBody({
    required this.critical, required this.incidents, required this.tasks,
    required this.ai, required this.email, required this.sms,
    required this.digest, required this.saveState,
    required this.onToggle, required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      ('critical',  'Critical Alerts',     'Push for P1/P2 incidents',          critical),
      ('incidents', 'Incident Updates',    'Status changes and escalations',     incidents),
      ('tasks',     'Task Updates',        'Assigned and completed tasks',       tasks),
      ('ai',        'AI Alerts',           'Predictive risk and anomaly flags',  ai),
      ('email',     'Email Notifications', 'To registered gov email',            email),
      ('sms',       'SMS Notifications',   'To registered mobile number',        sms),
      ('digest',    'Daily Digest',        'Summary at 8:00 AM IST',             digest),
    ];
    return Column(
      children: [
        const SizedBox(height: 8),
        for (final item in items)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: item == items.last
                      ? Colors.transparent
                      : AppColors.hairline,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.$2, style: AppTextStyles.bodySmallMedium),
                      Text(item.$3,
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.slate500.withOpacity(0.5))),
                    ],
                  ),
                ),
                NerToggle(
                    value: item.$4,
                    onChanged: (_) => onToggle(item.$1)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: saveState == 'saving' ? null : onSave,
            child: saveState == 'saving'
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(saveState == 'saved'
                    ? '✓ Preferences saved' : 'Save Preferences'),
          ),
        ),
      ],
    );
  }
}

// ── Theme body ───────────────────────────────────────────────────────────────
class _ThemeBody extends StatelessWidget {
  final String theme;
  final ValueChanged<String> onTheme;

  const _ThemeBody({required this.theme, required this.onTheme});

  @override
  Widget build(BuildContext context) {
    final options = [
      ('light',  'Light',  'Default platform theme',         Icons.wb_sunny_outlined),
      ('dark',   'Dark',   'Reduced eye strain at night',    Icons.nightlight_round_outlined),
      ('system', 'System', 'Follows OS preference',          Icons.phone_android_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: options.map((o) {
            final on = theme == o.$1;
            return Expanded(
              child: GestureDetector(
                onTap: () => onTheme(o.$1),
                child: Container(
                  margin: EdgeInsets.only(
                      right: o.$1 != 'system' ? 8 : 0),
                  padding: const EdgeInsets.symmetric(
                      vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: on
                        ? AppColors.gold.withOpacity(0.08)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: on
                          ? AppColors.gold
                          : AppColors.hairline,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: on ? AppColors.gold : AppColors.paper,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(o.$4,
                            size: 16,
                            color: on
                                ? Colors.white
                                : AppColors.slate500),
                      ),
                      const SizedBox(height: 6),
                      Text(o.$2,
                          style: AppTextStyles.captionSemibold.copyWith(
                            color: on
                                ? AppColors.gold
                                : AppColors.navy900,
                            fontWeight: FontWeight.w700,
                          )),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text('Applies instantly.',
            style: AppTextStyles.caption.copyWith(
                color: AppColors.slate500.withOpacity(0.45))),
      ],
    );
  }
}

// ── Language body ─────────────────────────────────────────────────────────────
class _LanguageBody extends StatelessWidget {
  final String language, saveState;
  final ValueChanged<String> onLanguage;
  final VoidCallback onApply;

  const _LanguageBody({
    required this.language, required this.saveState,
    required this.onLanguage, required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final langs = [
      ('en',  'English',   'English'),
      ('hi',  'हिन्दी',    'Hindi'),
      ('as',  'অসমীয়া',   'Assamese'),
      ('bn',  'বাংলা',     'Bengali'),
      ('brx', 'बड़ो',      'Bodo'),
      ('kha', 'Khasi',     'Khasi'),
    ];
    return Column(
      children: [
        const SizedBox(height: 8),
        for (final l in langs)
          InkWell(
            onTap: () => onLanguage(l.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: l.$1 != langs.last.$1
                        ? AppColors.hairline
                        : Colors.transparent,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.$2,
                            style: AppTextStyles.bodySmallMedium),
                        Text(l.$3,
                            style: AppTextStyles.caption.copyWith(
                                color: AppColors.slate500
                                    .withOpacity(0.5))),
                      ],
                    ),
                  ),
                  if (language == l.$1)
                    Icon(Icons.check_circle,
                        size: 18, color: AppColors.deepGreen700),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: saveState == 'saving' ? null : onApply,
            child: saveState == 'saving'
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(saveState == 'saved'
                    ? '✓ Language applied' : 'Apply Language'),
          ),
        ),
      ],
    );
  }
}

// ── Security body ─────────────────────────────────────────────────────────────
class _SecurityBody extends StatelessWidget {
  final bool twoFa;
  final ValueChanged<bool> onTwoFa;

  const _SecurityBody({required this.twoFa, required this.onTwoFa});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Two-Factor Authentication',
                        style: AppTextStyles.bodySmallMedium),
                    Text('OTP via registered mobile',
                        style: AppTextStyles.caption.copyWith(
                            color: AppColors.slate500.withOpacity(0.5))),
                  ],
                ),
              ),
              NerToggle(value: twoFa, onChanged: onTwoFa),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('CHANGE PASSWORD',
            style: AppTextStyles.eyebrow.copyWith(
                color: AppColors.slate500.withOpacity(0.5))),
        const SizedBox(height: 8),
        _SettingsField(
            label: 'Current Password',
            value: '',
            onChanged: (_) {},
            obscure: true),
        _SettingsField(
            label: 'New Password (min. 8 characters)',
            value: '',
            onChanged: (_) {},
            obscure: true),
        _SettingsField(
            label: 'Confirm New Password',
            value: '',
            onChanged: (_) {},
            obscure: true),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {},
            child: const Text('Change Password'),
          ),
        ),
      ],
    );
  }
}

// ── Shared settings form field ────────────────────────────────────────────────
class _SettingsField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final TextInputType keyboardType;
  final bool obscure;

  const _SettingsField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.keyboardType = TextInputType.text,
    this.obscure = false,
  });

  @override
  State<_SettingsField> createState() => _SettingsFieldState();
}

class _SettingsFieldState extends State<_SettingsField> {
  late final TextEditingController _ctrl;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.slate500.withOpacity(0.6))),
          const SizedBox(height: 4),
          TextFormField(
            controller: _ctrl,
            onChanged: widget.onChanged,
            keyboardType: widget.keyboardType,
            obscureText: widget.obscure && !_show,
            style: AppTextStyles.inputText,
            decoration: InputDecoration(
              suffixIcon: widget.obscure
                  ? IconButton(
                      icon: Icon(
                        _show
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: AppColors.slate500,
                      ),
                      onPressed: () => setState(() => _show = !_show),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
