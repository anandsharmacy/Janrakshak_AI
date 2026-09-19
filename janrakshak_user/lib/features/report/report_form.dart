import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../data/auth.dart';
import '../../data/providers.dart';
import '../../data/region_data.dart';
import '../../data/taxonomy.dart';
import 'report_service.dart';

enum LocationMode { auto, manual }

const maxMedia = 6;

class ReportState {
  const ReportState({
    this.mode = LocationMode.auto,
    this.detecting = false,
    this.detected,
    this.region,
    this.state,
    this.district,
    this.types = const {},
    this.severity,
    this.media = const [],
    this.progress = const {},
    this.submitting = false,
    this.result,
    this.resultDistrict,
    this.error,
  });

  final LocationMode mode;
  final bool detecting;
  final Place? detected;
  final String? region, state, district;
  final Set<String> types;
  final Severity? severity;
  final List<XFile> media;
  final Map<int, double> progress;
  final bool submitting;
  final SubmitResult? result;
  final String? resultDistrict, error;

  ReportState copyWith({
    LocationMode? mode, bool? detecting, Place? detected, String? Function()? region, String? Function()? state,
    String? Function()? district, Set<String>? types, Severity? Function()? severity, List<XFile>? media,
    Map<int, double>? progress, bool? submitting, SubmitResult? result, String? resultDistrict,
    String? Function()? error,
  }) =>
      ReportState(
        mode: mode ?? this.mode,
        detecting: detecting ?? this.detecting,
        detected: detected ?? this.detected,
        region: region != null ? region() : this.region,
        state: state != null ? state() : this.state,
        district: district != null ? district() : this.district,
        types: types ?? this.types,
        severity: severity != null ? severity() : this.severity,
        media: media ?? this.media,
        progress: progress ?? this.progress,
        submitting: submitting ?? this.submitting,
        result: result ?? this.result,
        resultDistrict: resultDistrict ?? this.resultDistrict,
        error: error != null ? error() : this.error,
      );

  /// Incident chips shown for the selected region only.
  List<String> get availableTypes => RegionData.regionToIncidentTypes[region] ?? const [];
}

class ReportForm extends Notifier<ReportState> {
  @override
  ReportState build() => const ReportState();

  Future<void> detect() async {
    state = state.copyWith(detecting: true, error: () => null);
    final pos = await currentPosition();
    final place = pos == null ? null : await reverseGeocode(LatLng(pos.latitude, pos.longitude));
    if (place?.state == null) {
      state = state.copyWith(
          detecting: false,
          mode: LocationMode.manual,
          error: () => "Couldn't detect your location - choose it manually.");
      return;
    }
    _apply(place!.region, place.state, place.district, detected: place, detecting: false);
  }

  void _apply(String? region, String? st, String? district, {Place? detected, bool detecting = false}) {
    final keep = state.types.where((t) => (RegionData.regionToIncidentTypes[region] ?? const []).contains(t));
    state = state.copyWith(
      detected: detected, detecting: detecting, region: () => region, state: () => st, district: () => district,
      types: keep.toSet(),
    );
  }

  void setMode(LocationMode m) {
    if (m == LocationMode.auto) {
      state = state.copyWith(mode: m);
      if (state.detected == null) detect();
    } else {
      state = state.copyWith(mode: m); // keeps any detected values as the starting point for editing
    }
  }

  void setRegion(String? r) => _apply(r, null, null);
  void setState(String? s) => _apply(state.region, s, null);
  void setDistrict(String? d) => state = state.copyWith(district: () => d);

  void toggleType(String t) {
    final s = {...state.types};
    s.contains(t) ? s.remove(t) : s.add(t);
    state = state.copyWith(types: s);
  }

  void setSeverity(Severity? s) => state = state.copyWith(severity: () => s);

  void addMedia(Iterable<XFile> files) =>
      state = state.copyWith(media: [...state.media, ...files].take(maxMedia).toList());

  void removeMedia(int i) => state = state.copyWith(media: [...state.media]..removeAt(i));

  void reset() => state = const ReportState();

  Future<void> submit(String description) async {
    final s = state;
    final problem = s.state == null || s.district == null
        ? 'Choose your State and District (or use auto-detect).'
        : s.types.isEmpty
            ? 'Select at least one incident type.'
            : null;
    if (problem != null) {
      state = s.copyWith(error: () => problem);
      return;
    }
    state = s.copyWith(submitting: true, progress: {}, error: () => null);
    final pos = s.mode == LocationMode.auto ? s.detected?.pos : null;
    final report = Report(
      id: const Uuid().v4(),
      userId: ref.read(sessionProvider).value?.user.id,
      state: s.state!, district: s.district!, types: s.types.toList(), description: description.trim(),
      lat: pos?.latitude, lng: pos?.longitude, severity: s.severity?.label,
      mediaPaths: [for (final f in s.media) f.path],
    );
    try {
      final r = await submitReport(report,
          onProgress: (i, p) => state = state.copyWith(progress: {...state.progress, i: p}));
      state = state.copyWith(submitting: false, result: r, resultDistrict: s.district);
    } catch (e) {
      state = state.copyWith(submitting: false, error: () => "Couldn't save the report: $e");
    }
  }
}

final reportFormProvider = NotifierProvider<ReportForm, ReportState>(ReportForm.new);
