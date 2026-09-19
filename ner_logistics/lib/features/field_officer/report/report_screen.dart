import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../mock_data/models.dart';
import '../../../mock_data/mock_repository.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../theme/colors.dart';
import '../../../theme/text_styles.dart';

/// ReportScreen — 6-step incident report wizard.
/// Steps: Type → Location → Evidence → Details → Review → Success
class ReportScreen extends ConsumerStatefulWidget {
  final IncidentType? initialType;
  const ReportScreen({super.key, this.initialType});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  late int _step; // 1–6
  IncidentType? _type;
  String _severity = 'moderate';
  String _description = '';
  bool _photoAdded = false;
  bool _submitting = false;
  bool _submitted = false;
  SyncStatus _sync = SyncStatus.pending;

  static const _stepLabels = [
    'Type', 'Location', 'Evidence', 'Details', 'Review', 'Submit'
  ];

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _step = widget.initialType != null ? 2 : 1;
  }

  void _next() => setState(() => _step = (_step + 1).clamp(1, 6));
  void _back() => setState(() => _step = (_step - 1).clamp(1, 6));

  Future<void> _submit() async {
    setState(() => _submitting = true);
    await Future.delayed(const Duration(seconds: 2));
    final report = IncidentReport(
      id: 'RPT-${DateTime.now().millisecondsSinceEpoch}',
      type: _type,
      location: 'NH-6 Km 22, Dimapur corridor',
      gpsCoords: '25.5781, 91.8933',
      severity: _severity,
      description: _description,
      syncStatus: ref.read(mockRepositoryProvider).isOffline
          ? SyncStatus.pending
          : SyncStatus.synced,
    );
    ref.read(mockRepositoryProvider.notifier).queueReport(report);
    setState(() {
      _submitting = false;
      _submitted = true;
      _sync = report.syncStatus;
      _step = 6;
    });
  }

  void _reset() => setState(() {
        _step = 1;
        _type = null;
        _severity = 'moderate';
        _description = '';
        _photoAdded = false;
        _submitting = false;
        _submitted = false;
        _sync = SyncStatus.pending;
      });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Progress stepper (steps 1–5)
        if (_step < 6)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                Row(
                  children: List.generate(_stepLabels.length, (i) {
                    final n = i + 1;
                    final done = n < _step;
                    final active = n == _step;
                    return Expanded(
                      child: Column(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: done
                                  ? AppColors.deepGreen700
                                  : active
                                      ? AppColors.navy900
                                      : AppColors.slate500
                                          .withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: done
                                ? const Icon(Icons.check,
                                    size: 12, color: Colors.white)
                                : Center(
                                    child: Text('$n',
                                        style: AppTextStyles.eyebrow
                                            .copyWith(
                                          color: active
                                              ? Colors.white
                                              : AppColors.slate500
                                                  .withOpacity(0.5),
                                          fontSize: 11,
                                        )),
                                  ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _stepLabels[i],
                            style: AppTextStyles.eyebrow.copyWith(
                              color: active
                                  ? AppColors.navy900
                                  : done
                                      ? AppColors.deepGreen700
                                      : AppColors.slate500
                                          .withOpacity(0.4),
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_step - 1) / 5,
                    backgroundColor:
                        AppColors.slate500.withOpacity(0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.navy900),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        // Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildStep(),
          ),
        ),
        // Back nav
        if (_step >= 2 && _step <= 5)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            child: TextButton.icon(
              onPressed: _back,
              icon: const Icon(Icons.arrow_back_ios, size: 14),
              label: Text('Back to ${_stepLabels[_step - 2]}'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.navy900.withOpacity(0.7),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 1: return _Step1(selected: _type, onSelect: (t) {
        setState(() { _type = t; _next(); });
      });
      case 2: return _Step2(onNext: _next);
      case 3: return _Step3(
        photoAdded: _photoAdded,
        onToggle: () => setState(() => _photoAdded = !_photoAdded),
        onNext: _next,
      );
      case 4: return _Step4(
        severity: _severity,
        description: _description,
        onSeverity: (s) => setState(() => _severity = s),
        onDescription: (d) => setState(() => _description = d),
        onNext: _next,
      );
      case 5: return _Step5(
        type: _type,
        severity: _severity,
        description: _description,
        photoAdded: _photoAdded,
        sync: _sync,
        submitting: _submitting,
        onSubmit: _submit,
        onEdit: _back,
      );
      case 6: return _Step6(
        type: _type,
        sync: _sync,
        onNewReport: _reset,
      );
      default: return const SizedBox.shrink();
    }
  }
}

// ── Step 1 — Type ─────────────────────────────────────────────────────────────

class _Step1 extends StatelessWidget {
  final IncidentType? selected;
  final ValueChanged<IncidentType> onSelect;
  const _Step1({required this.selected, required this.onSelect});

  static const _types = [
    (IncidentType.roadBlockage, 'Road Blockage', '🚧',
        'border-saffron/50'),
    (IncidentType.flood,        'Flood',         '🌊', 'border-green'),
    (IncidentType.landslide,    'Landslide',     '⛰️', 'border-red'),
    (IncidentType.accident,     'Accident',      '🚗', 'border-navy'),
    (IncidentType.infraDamage,  'Infra Damage',  '🏗️', 'border-ink'),
    (IncidentType.other,        'Other',         '📋', 'border-hair'),
  ];

  Color _borderColor(String key) {
    switch (key) {
      case 'border-saffron/50': return AppColors.saffron600.withOpacity(0.5);
      case 'border-green':      return AppColors.deepGreen700.withOpacity(0.4);
      case 'border-red':        return AppColors.signalRed700.withOpacity(0.4);
      case 'border-navy':       return AppColors.navy900.withOpacity(0.3);
      case 'border-ink':        return AppColors.slate500.withOpacity(0.2);
      default:                  return AppColors.hairline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What happened?', style: AppTextStyles.sectionHeading),
        const SizedBox(height: 4),
        Text('Select the incident type',
            style: AppTextStyles.bodySmall),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: _types.map((t) {
            final on = selected == t.$1;
            return GestureDetector(
              onTap: () => onSelect(t.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: on
                        ? AppColors.navy900
                        : _borderColor(t.$4),
                    width: on ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(t.$3,
                        style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: 6),
                    Text(t.$2,
                        style: AppTextStyles.captionSemibold
                            .copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.navy900),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Step 2 — Location ─────────────────────────────────────────────────────────

class _Step2 extends StatelessWidget {
  final VoidCallback onNext;
  const _Step2({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Location', style: AppTextStyles.sectionHeading),
        Text('GPS auto-detected · verify or adjust',
            style: AppTextStyles.bodySmall),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.deepGreen700.withOpacity(0.05),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: AppColors.deepGreen700.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.location_on_outlined,
                  size: 18, color: AppColors.deepGreen700),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('GPS locked',
                      style: AppTextStyles.captionSemibold.copyWith(
                          color: AppColors.deepGreen700,
                          fontWeight: FontWeight.w700)),
                  Text('25.5713° N, 91.8827° E · ±4m',
                      style: AppTextStyles.caption),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 140,
          decoration: BoxDecoration(
            color: const Color(0xFFD8E4D4),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.push_pin_outlined,
                    size: 28,
                    color: AppColors.slate500.withOpacity(0.4)),
                Text('NH-6, near Km 26 junction',
                    style: AppTextStyles.caption),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        LabeledInput(
            label: 'Location name',
            initialValue: 'NH-6, Km 26 junction'),
        LabeledInput(
            label: 'Route / road',
            initialValue: 'National Highway 6'),
        LabeledInput(
            label: 'Nearest landmark',
            placeholder: 'Bridge, junction, km marker…'),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('Continue to Evidence'),
          ),
        ),
      ],
    );
  }
}

// ── Step 3 — Evidence ─────────────────────────────────────────────────────────

class _Step3 extends StatelessWidget {
  final bool photoAdded;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  const _Step3(
      {required this.photoAdded,
      required this.onToggle,
      required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Evidence', style: AppTextStyles.sectionHeading),
        Text('Photo or video — GPS & timestamp auto-attached',
            style: AppTextStyles.bodySmall),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onToggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 160,
            decoration: BoxDecoration(
              color: photoAdded
                  ? AppColors.deepGreen700.withOpacity(0.05)
                  : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: photoAdded
                    ? AppColors.deepGreen700.withOpacity(0.5)
                    : AppColors.slate500.withOpacity(0.2),
                width: 2,
                style: photoAdded
                    ? BorderStyle.solid
                    : BorderStyle.solid,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    photoAdded
                        ? Icons.check_circle_outline
                        : Icons.camera_alt_outlined,
                    size: 28,
                    color: photoAdded
                        ? AppColors.deepGreen700
                        : AppColors.slate500.withOpacity(0.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    photoAdded
                        ? '1 photo added'
                        : 'Add photo or video',
                    style: AppTextStyles.cardTitle.copyWith(
                      color: photoAdded
                          ? AppColors.deepGreen700
                          : AppColors.navy900,
                    ),
                  ),
                  Text(
                    photoAdded ? 'Tap to remove' : 'Tap to capture or upload',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onToggle,
          icon: const Icon(Icons.cloud_upload_outlined, size: 18),
          label: const Text('Upload from gallery'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Icon(Icons.access_time_outlined,
                  size: 15,
                  color: AppColors.slate500.withOpacity(0.4)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Timestamp: 09:41:33 · GPS: 25.5713° N, 91.8827° E · Device: Field tablet',
                  style: AppTextStyles.caption.copyWith(
                      color: AppColors.slate500.withOpacity(0.6)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('Continue to Details'),
          ),
        ),
      ],
    );
  }
}

// ── Step 4 — Details ──────────────────────────────────────────────────────────

class _Step4 extends StatelessWidget {
  final String severity;
  final String description;
  final ValueChanged<String> onSeverity;
  final ValueChanged<String> onDescription;
  final VoidCallback onNext;

  const _Step4({
    required this.severity,
    required this.description,
    required this.onSeverity,
    required this.onDescription,
    required this.onNext,
  });

  static const _severities = [
    ('low',      'Low'),
    ('moderate', 'Moderate'),
    ('high',     'High'),
    ('critical', 'Critical'),
  ];

  Color _sevColor(String s) {
    switch (s) {
      case 'low':      return AppColors.deepGreen700;
      case 'moderate': return AppColors.saffron600;
      case 'high':     return AppColors.saffron600;
      case 'critical': return AppColors.signalRed700;
      default:         return AppColors.navy900;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Incident details', style: AppTextStyles.sectionHeading),
        Text('Describe what you observed',
            style: AppTextStyles.bodySmall),
        const SizedBox(height: 16),
        FieldLabel('Severity'),
        const SizedBox(height: 8),
        Row(
          children: _severities.map((s) {
            final on = severity == s.$1;
            final c = _sevColor(s.$1);
            return Expanded(
              child: GestureDetector(
                onTap: () => onSeverity(s.$1),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: on ? c.withOpacity(0.1) : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: on ? c : AppColors.hairline,
                      width: on ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    s.$2,
                    style: AppTextStyles.eyebrow.copyWith(
                      color: on ? c : AppColors.slate500,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        FieldLabel('Description'),
        const SizedBox(height: 8),
        TextField(
          maxLines: 4,
          onChanged: onDescription,
          style: AppTextStyles.inputText,
          decoration: InputDecoration(
            hintText:
                'Describe what you see — road condition, extent of damage…',
            hintStyle: AppTextStyles.inputHint,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: LabeledSelect(
                label: 'Road condition',
                options: const [
                  'Blocked',
                  'Partially blocked',
                  'Passable',
                  'Damaged'
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledSelect(
                label: 'Accessibility',
                options: const [
                  'No access',
                  'Emergency only',
                  'Single lane',
                  'Full access'
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('Review report'),
          ),
        ),
      ],
    );
  }
}

// ── Step 5 — Review ───────────────────────────────────────────────────────────

class _Step5 extends StatelessWidget {
  final IncidentType? type;
  final String severity, description;
  final bool photoAdded, submitting;
  final SyncStatus sync;
  final VoidCallback onSubmit, onEdit;

  const _Step5({
    required this.type,
    required this.severity,
    required this.description,
    required this.photoAdded,
    required this.submitting,
    required this.sync,
    required this.onSubmit,
    required this.onEdit,
  });

  String _typeLabel(IncidentType? t) {
    if (t == null) return '—';
    switch (t) {
      case IncidentType.roadBlockage: return 'Road Blockage';
      case IncidentType.flood:        return 'Flood';
      case IncidentType.landslide:    return 'Landslide';
      case IncidentType.accident:     return 'Accident';
      case IncidentType.infraDamage:  return 'Infra Damage';
      case IncidentType.other:        return 'Other';
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Incident type',  _typeLabel(type)),
      ('Severity',       severity[0].toUpperCase() + severity.substring(1)),
      ('Location',       'NH-6, Km 26 junction'),
      ('GPS',            '25.5713° N, 91.8827° E'),
      ('Photo',          photoAdded ? '1 photo attached' : 'No photo'),
      ('Description',    description.isEmpty ? 'No description' : description),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Review & submit', style: AppTextStyles.sectionHeading),
        Text('Confirm details before submitting',
            style: AppTextStyles.bodySmall),
        const SizedBox(height: 16),
        CardSurface(
          child: Column(
            children: rows.asMap().entries.map((e) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: e.key < rows.length - 1
                      ? Border(
                          bottom:
                              BorderSide(color: AppColors.hairline))
                      : null,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(e.value.$1,
                          style: AppTextStyles.caption),
                    ),
                    Expanded(
                      child: Text(e.value.$2,
                          style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.navy900)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              SyncChip(status: sync),
              const SizedBox(width: 10),
              Text('Saved locally · will sync when online',
                  style: AppTextStyles.caption),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: submitting ? null : onSubmit,
            child: submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Text('Submit report'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: onEdit,
            child: const Text('Edit details'),
          ),
        ),
      ],
    );
  }
}

// ── Step 6 — Success ──────────────────────────────────────────────────────────

class _Step6 extends StatelessWidget {
  final IncidentType? type;
  final SyncStatus sync;
  final VoidCallback onNewReport;
  const _Step6(
      {required this.type,
      required this.sync,
      required this.onNewReport});

  String _typeLabel(IncidentType? t) {
    if (t == null) return 'Incident';
    switch (t) {
      case IncidentType.roadBlockage: return 'Road Blockage';
      case IncidentType.flood:        return 'Flood';
      case IncidentType.landslide:    return 'Landslide';
      case IncidentType.accident:     return 'Accident';
      case IncidentType.infraDamage:  return 'Infra Damage';
      case IncidentType.other:        return 'Other';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 32),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.deepGreen700.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(
                color: AppColors.deepGreen700.withOpacity(0.4),
                width: 2),
          ),
          child: Icon(Icons.check,
              size: 28, color: AppColors.deepGreen700),
        ),
        const SizedBox(height: 16),
        Text('Reported ✓', style: AppTextStyles.pageHeading),
        const SizedBox(height: 4),
        Text('${_typeLabel(type)} report submitted',
            style: AppTextStyles.bodySmall),
        const SizedBox(height: 24),
        CardSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _SuccessRow('Incident ID', 'INC-2295'),
              _SuccessRow('Status', 'Under review'),
              _SuccessRow('Notified',
                  'District officer + control room'),
              Row(
                children: [
                  Expanded(
                    child: Text('Sync status',
                        style: AppTextStyles.caption)),
                  SyncChip(status: sync),
                ],
              ),
            ].map((w) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: w is Row
                      ? w
                      : Divider(
                          color: AppColors.hairline, height: 1),
                )).toList(),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.deepGreen700.withOpacity(0.05),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: AppColors.deepGreen700.withOpacity(0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_outlined,
                  size: 15, color: AppColors.deepGreen700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'District officer has been notified. Response ETA: 15–30 min. You will receive an update when the report is verified.',
                  style: AppTextStyles.caption.copyWith(
                      color: AppColors.navy900.withOpacity(0.8)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onNewReport,
            child: const Text('Report another incident'),
          ),
        ),
      ],
    );
  }
}

class _SuccessRow extends StatelessWidget {
  final String label, value;
  const _SuccessRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.caption)),
          Text(value,
              style: AppTextStyles.captionSemibold.copyWith(
                  color: AppColors.navy900,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
