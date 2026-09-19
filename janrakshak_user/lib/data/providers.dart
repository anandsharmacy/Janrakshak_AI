import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:latlong2/latlong.dart';

import 'region_data.dart';
import 'store.dart';

bool _isOnline(List<ConnectivityResult> r) => r.isNotEmpty && !r.contains(ConnectivityResult.none);

Future<bool> isOnline() async => _isOnline(await Connectivity().checkConnectivity());

final onlineProvider = StreamProvider<bool>((ref) async* {
  yield await isOnline();
  yield* Connectivity().onConnectivityChanged.map(_isOnline).distinct();
});

/// Hive box length as a live count.
StreamProvider<int> boxCountProvider(Box<String> Function() box) => StreamProvider<int>((ref) async* {
      yield box().length;
      yield* box().watch().map((_) => box().length);
    });

final pendingCountProvider = boxCountProvider(() => Store.pendingReports);
final tripCountProvider = boxCountProvider(() => Store.trips);

Future<bool>? _permission;

/// One shared in-flight permission request (concurrent requests make geolocator throw); failures are retried next call.
Future<bool> _ensurePermission() => _permission ??= () async {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      return perm != LocationPermission.denied && perm != LocationPermission.deniedForever;
    }()
        .then((ok) {
      if (!ok) _permission = null;
      return ok;
    }, onError: (Object _) {
      _permission = null;
      return false;
    });

/// Current GPS fix, or null if services/permission are off. Never throws.
Future<Position?> currentPosition() async {
  try {
    if (!await _ensurePermission()) return null;
    return await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)));
  } catch (_) {
    return null;
  }
}

final positionProvider = FutureProvider<Position?>((ref) => currentPosition());

// The platform geocoder can hang without a Google backend or signal; fall back instead of waiting forever.
const _geocodeTimeout = Duration(seconds: 6);

class Place {
  const Place({required this.pos, this.state, this.district, this.name});
  final LatLng pos;
  final String? state, district, name;
  String? get region => state == null ? null : RegionData.regionOf(state!);
  String get label => name ?? district ?? '${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)}';

  Map<String, dynamic> toJson() => {'lat': pos.latitude, 'lng': pos.longitude, 'name': label};
  factory Place.fromJson(Map<String, dynamic> j) =>
      Place(pos: LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()), name: j['name']);
}

/// Forward-geocode free text ("Port Blair"); null when nothing matches or the geocoder is unreachable.
Future<Place?> geocodeQuery(String q) async {
  try {
    final l = (await Geocoding().locationFromAddress('$q, India').timeout(_geocodeTimeout)).firstOrNull;
    return l == null ? null : Place(pos: LatLng(l.latitude, l.longitude), name: q.trim());
  } catch (_) {
    return null;
  }
}

/// Reverse-geocode to canonical State/District. Falls back to coordinates only when offline.
Future<Place> reverseGeocode(LatLng p) async {
  try {
    final m = (await Geocoding().placemarkFromCoordinates(p.latitude, p.longitude).timeout(_geocodeTimeout)).first;
    final state = RegionData.matchState(m.administrativeArea);
    final district = state == null
        ? null
        : RegionData.matchDistrict(state, m.subAdministrativeArea) ?? RegionData.matchDistrict(state, m.locality);
    return Place(pos: p, state: state, district: district, name: m.locality ?? m.subAdministrativeArea);
  } catch (_) {
    return Place(pos: p);
  }
}

/// The user's own place (GPS + reverse geocode), or null without a fix.
final myPlaceProvider = FutureProvider<Place?>((ref) async {
  final pos = await ref.watch(positionProvider.future);
  return pos == null ? null : reverseGeocode(LatLng(pos.latitude, pos.longitude));
});
