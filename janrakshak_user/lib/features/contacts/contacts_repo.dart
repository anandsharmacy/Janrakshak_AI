import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/hazard.dart';
import '../../data/providers.dart';
import '../../data/seed_data.dart';
import '../../data/store.dart';

const _cacheKey = 'directory';

/// Cache-first: renders from Hive instantly (works with zero connectivity), else loads once and caches.
// ponytail: the "remote" source is the bundled seed list; point _fetch at the backend and add a refresh when one exists.
final contactsProvider = FutureProvider<List<Contact>>((ref) async {
  final cached = Store.contacts.get(_cacheKey);
  if (cached != null) {
    return [for (final j in jsonDecode(cached) as List) Contact.fromJson(j as Map<String, dynamic>)];
  }
  final fresh = _fetch();
  await Store.contacts.put(_cacheKey, jsonEncode([for (final c in fresh) c.toJson()]));
  return fresh;
});

List<Contact> _fetch() => seedContacts;

class DistrictFilter extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? d) => state = d;
}

final districtFilterProvider = NotifierProvider<DistrictFilter, String?>(DistrictFilter.new);

class Ranked {
  const Ranked(this.contact, this.km);
  final Contact contact;
  final double? km;
}

/// Filtered by district, nearest first when GPS is available, otherwise alphabetical.
final rankedContactsProvider = Provider<AsyncValue<List<Ranked>>>((ref) {
  final district = ref.watch(districtFilterProvider);
  final pos = ref.watch(positionProvider).value;
  final here = pos == null ? null : LatLng(pos.latitude, pos.longitude);
  return ref.watch(contactsProvider).whenData((all) {
    final list = [
      for (final c in all)
        if (district == null || c.district == district) Ranked(c, here == null ? null : distanceKm(here, c.pos)),
    ];
    list.sort((a, b) => here == null ? a.contact.name.compareTo(b.contact.name) : a.km!.compareTo(b.km!));
    return list;
  });
});

Future<bool> _open(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('launch $uri failed: $e');
    return false;
  }
}

Future<bool> callNumber(String number) => _open(Uri(scheme: 'tel', path: number));
Future<bool> navigateTo(LatLng p) =>
    _open(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${p.latitude},${p.longitude}'));
