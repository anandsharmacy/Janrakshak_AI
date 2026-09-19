import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/region_data.dart';
import '../../data/taxonomy.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'report_form.dart';
import 'report_service.dart';

const _videoExt = {'.mp4', '.mov', '.3gp', '.mkv', '.webm'};

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});
  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _desc = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(reportFormProvider.notifier).detect());
  }

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pick(Future<List<XFile>> Function() picker) async {
    try {
      ref.read(reportFormProvider.notifier).addMedia(await picker());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Couldn't open the camera or gallery. Check permissions.")));
      }
    }
  }

  Future<List<XFile>> _one(Future<XFile?> f) async => [?await f];

  void _submit() {
    final f = ref.read(reportFormProvider.notifier);
    if (!_formKey.currentState!.validate()) return;
    f.submit(_desc.text);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(reportFormProvider);
    final f = ref.read(reportFormProvider.notifier);
    final text = Theme.of(context).textTheme;

    if (s.result != null) {
      return _Done(s, onAgain: () {
        _desc.clear();
        f.reset();
        f.detect();
      });
    }

    return SafeArea(
      bottom: false,
      child: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const ScreenHeader(eyebrow: 'Report an incident', title: 'What is happening?'),
          const SizedBox(height: 16),
          SegmentedButton<LocationMode>(
            segments: const [
              ButtonSegment(value: LocationMode.auto, label: Text('Auto-detect'), icon: Icon(Icons.my_location_outlined)),
              ButtonSegment(value: LocationMode.manual, label: Text('Manual'), icon: Icon(Icons.edit_location_alt_outlined)),
            ],
            selected: {s.mode},
            onSelectionChanged: (v) => f.setMode(v.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 12),
          if (s.mode == LocationMode.auto) _AutoLocation(s) else _ManualLocation(s),
          const SizedBox(height: 20),
          const Eyebrow('Incident type'),
          const SizedBox(height: 8),
          if (s.availableTypes.isEmpty)
            Text('Choose a location to see incident types for your region.',
                style: text.bodyMedium?.copyWith(color: AppTheme.mutedOnDark))
          else
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final t in s.availableTypes)
                FilterChip(
                  avatar: Icon(incidentIcon(t), size: 18),
                  label: Text(t),
                  selected: s.types.contains(t),
                  onSelected: (_) => f.toggleType(t),
                ),
            ]),
          const SizedBox(height: 20),
          const Eyebrow('Photos / video'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            PillButton(
                label: 'Photo', icon: Icons.photo_camera_outlined, outlined: true,
                onPressed: () => _pick(() => _one(ImagePicker().pickImage(source: ImageSource.camera)))),
            PillButton(
                label: 'Video', icon: Icons.videocam_outlined, outlined: true,
                onPressed: () => _pick(() => _one(ImagePicker().pickVideo(source: ImageSource.camera)))),
            PillButton(
                label: 'Gallery', icon: Icons.photo_library_outlined, outlined: true,
                onPressed: () => _pick(() => ImagePicker().pickMultipleMedia(limit: maxMedia))),
          ]),
          if (s.media.isNotEmpty) ...[const SizedBox(height: 12), _MediaGrid(s)],
          const SizedBox(height: 20),
          const Eyebrow('Description'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _desc,
            maxLength: 500,
            minLines: 4,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Water entering homes near the market; road to the school is cut off.',
              helperText: 'At least 10 characters: what happened, where exactly, and who needs help.',
              helperMaxLines: 2,
            ),
            validator: (v) => (v?.trim().length ?? 0) < 10 ? 'Please describe the incident (10+ characters).' : null,
          ),
          const SizedBox(height: 12),
          const Eyebrow('Severity (optional)'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final v in Severity.values)
              ChoiceChip(
                avatar: CircleAvatar(backgroundColor: v.color, radius: 6),
                label: Text(v.label),
                selected: s.severity == v,
                selectedColor: v.color,
                labelStyle: TextStyle(
                    color: s.severity == v ? AppColors.textOnDark : null, fontWeight: FontWeight.w600),
                onSelected: (sel) => f.setSeverity(sel ? v : null),
              ),
          ]),
          if (s.error != null) ...[
            const SizedBox(height: 16),
            StatusBanner(lead: 'Cannot submit yet.', text: s.error!, color: AppColors.statusCritical, icon: Icons.error_outline),
          ],
          const SizedBox(height: 20),
          PillButton(
            label: s.submitting ? 'Sending...' : 'Submit report',
            icon: Icons.send_outlined,
            expand: true,
            onPressed: s.submitting ? null : _submit,
          ),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}

class _AutoLocation extends ConsumerWidget {
  const _AutoLocation(this.s);
  final ReportState s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.read(reportFormProvider.notifier);
    if (s.detecting) {
      return const Row(children: [
        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Text('Detecting your location...'),
      ]);
    }
    if (s.state == null) {
      return Align(
          alignment: Alignment.centerLeft,
          child: PillButton(label: 'Detect again', icon: Icons.refresh_outlined, outlined: true, onPressed: f.detect));
    }
    final label = [if (s.district != null) s.district!, s.state!, if (s.region != null) '${s.region} region'].join(' · ');
    // Editable confirm chip: tapping it drops into manual mode with these values prefilled.
    return Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      InputChip(
        avatar: const Icon(Icons.place_outlined, size: 18),
        label: Text(label),
        deleteIcon: const Icon(Icons.edit_outlined, size: 18),
        onDeleted: () => f.setMode(LocationMode.manual),
        onPressed: () => f.setMode(LocationMode.manual),
      ),
      if (s.district == null)
        const Text('District not matched - tap to edit', style: TextStyle(color: AppTheme.mutedOnDark)),
    ]);
  }
}

class _ManualLocation extends ConsumerWidget {
  const _ManualLocation(this.s);
  final ReportState s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.read(reportFormProvider.notifier);
    Widget dd(String label, String? value, List<String> items, ValueChanged<String?> on, Key k) =>
        DropdownButtonFormField<String>(
          key: k,
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          dropdownColor: AppColors.bgRaised,
          items: [for (final i in items) DropdownMenuItem(value: i, child: Text(i, overflow: TextOverflow.ellipsis))],
          onChanged: on,
        );
    return Column(children: [
      dd('Region', s.region, RegionData.regionToStates.keys.toList(), f.setRegion, const ValueKey('region')),
      const SizedBox(height: 12),
      dd('State / UT', s.state, RegionData.regionToStates[s.region] ?? const [], f.setState, ValueKey('st-${s.region}-${s.state}')),
      const SizedBox(height: 12),
      dd('District', s.district, RegionData.stateToDistricts[s.state] ?? const [], f.setDistrict,
          ValueKey('d-${s.state}-${s.district}')),
    ]);
  }
}

class _MediaGrid extends ConsumerWidget {
  const _MediaGrid(this.s);
  final ReportState s;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 120, mainAxisSpacing: 8, crossAxisSpacing: 8),
        itemCount: s.media.length,
        itemBuilder: (_, i) {
          final path = s.media[i].path;
          final isVideo = _videoExt.any(path.toLowerCase().endsWith);
          final p = s.progress[i];
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(fit: StackFit.expand, children: [
              isVideo
                  ? Container(color: AppColors.bgRaised, child: const Icon(Icons.play_circle_outline, size: 40))
                  : Image.file(File(path), fit: BoxFit.cover, cacheWidth: 240,
                      errorBuilder: (_, _, _) => Container(color: AppColors.bgRaised, child: const Icon(Icons.broken_image_outlined))),
              if (!s.submitting)
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_outlined),
                    style: IconButton.styleFrom(backgroundColor: AppColors.bgDark.withAlpha(180)),
                    onPressed: () => ref.read(reportFormProvider.notifier).removeMedia(i),
                  ),
                ),
              if (s.submitting)
                Positioned(left: 0, right: 0, bottom: 0, child: LinearProgressIndicator(value: p ?? 0)),
            ]),
          );
        },
      );
}

class _Done extends StatelessWidget {
  const _Done(this.s, {required this.onAgain});
  final ReportState s;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final sent = s.result == SubmitResult.sent;
    final where = s.resultDistrict ?? 'your area';
    return SafeArea(
      bottom: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(sent ? Icons.check_circle_outline : Icons.cloud_off_outlined,
                size: 72, color: sent ? AppColors.statusOk : AppColors.accent),
            const SizedBox(height: 16),
            Text(sent ? 'Report received' : 'Saved offline', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              sent
                  ? 'Report received — routed to your nearest Field Officer for $where.'
                  : "You're offline. Your report for $where is saved and will be sent automatically when you're back online.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            PillButton(label: 'Report another', icon: Icons.add_outlined, outlined: true, onPressed: onAgain),
          ]),
        ),
      ),
    );
  }
}
