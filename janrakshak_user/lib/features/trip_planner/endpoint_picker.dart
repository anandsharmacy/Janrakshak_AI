import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/providers.dart';
import '../../data/region_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dark_map.dart';
import '../../widgets/widgets.dart';

/// Bottom sheet to choose a From/To point: place search, region/state/district, GPS, or a map pin.
Future<Place?> pickEndpoint(BuildContext context, String title) => showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgDark,
      builder: (_) => _PickerSheet(title),
    );

class _PickerSheet extends ConsumerStatefulWidget {
  const _PickerSheet(this.title);
  final String title;
  @override
  ConsumerState<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends ConsumerState<_PickerSheet> {
  final _q = TextEditingController();
  String? _region, _state, _district, _error;
  bool _busy = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _resolve(Future<Place?> Function() f, String failure) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final p = await f();
    if (!mounted) return;
    if (p == null) {
      setState(() {
        _busy = false;
        _error = failure;
      });
    } else {
      Navigator.pop(context, p);
    }
  }

  Future<void> _pin() async {
    final pos = await Navigator.push<LatLng>(context, MaterialPageRoute(builder: (_) => const _MapPinPage()));
    if (pos == null || !mounted) return;
    _resolve(() async {
      final p = await reverseGeocode(pos);
      return Place(pos: pos, state: p.state, district: p.district, name: p.name ?? 'Pinned location');
    }, '');
  }

  @override
  Widget build(BuildContext context) {
    final dropdownStyle = InputDecoration(labelText: null, filled: true, fillColor: AppColors.bgRaised);
    Widget dd(String label, String? v, List<String> items, ValueChanged<String?> on) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DropdownButtonFormField<String>(
            key: ValueKey('$label-$v-${items.length}'),
            initialValue: v,
            isExpanded: true,
            decoration: dropdownStyle.copyWith(labelText: label),
            dropdownColor: AppColors.bgRaised,
            items: [for (final i in items) DropdownMenuItem(value: i, child: Text(i, overflow: TextOverflow.ellipsis))],
            onChanged: on,
          ),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
          Eyebrow(widget.title),
          const SizedBox(height: 8),
          TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search a place, e.g. Silchar',
              prefixIcon: const Icon(Icons.search_outlined),
              suffixIcon: IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.arrow_forward_outlined),
                  onPressed: () => _resolve(() => geocodeQuery(_q.text), 'No match. Check the name or your connection.')),
            ),
            onSubmitted: (v) => _resolve(() => geocodeQuery(v), 'No match. Check the name or your connection.'),
          ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
          if (_error != null && _error!.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: StatusBanner(lead: 'Not found.', text: _error!, color: AppColors.statusCritical, icon: Icons.error_outline)),
          ListTile(
            leading: const Icon(Icons.my_location_outlined),
            title: const Text('Use my current location'),
            onTap: () => _resolve(() async {
              final me = await ref.read(myPlaceProvider.future);
              return me == null ? null : Place(pos: me.pos, state: me.state, district: me.district, name: 'My location');
            }, 'Location is off or permission was denied.'),
          ),
          ListTile(leading: const Icon(Icons.push_pin_outlined), title: const Text('Drop a pin on the map'), onTap: _pin),
          ExpansionTile(
            leading: const Icon(Icons.map_outlined),
            title: const Text('Choose region / state / district'),
            shape: const Border(),
            collapsedShape: const Border(),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              dd('Region', _region, RegionData.regionToStates.keys.toList(),
                  (v) => setState(() {
                    _region = v;
                    _state = null;
                    _district = null;
                  })),
              dd('State / UT', _state, RegionData.regionToStates[_region] ?? const [],
                  (v) => setState(() {
                    _state = v;
                    _district = null;
                  })),
              dd('District', _district, RegionData.stateToDistricts[_state] ?? const [], (v) => setState(() => _district = v)),
              PillButton(
                label: 'Use this district',
                expand: true,
                onPressed: _district == null
                    ? null
                    : () => _resolve(() async {
                          final p = await geocodeQuery('$_district, $_state');
                          return p == null ? null : Place(pos: p.pos, state: _state, district: _district, name: '$_district, $_state');
                        }, 'Could not locate that district. Check your connection.'),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}

class _MapPinPage extends StatefulWidget {
  const _MapPinPage();
  @override
  State<_MapPinPage> createState() => _MapPinPageState();
}

class _MapPinPageState extends State<_MapPinPage> {
  LatLng? _pin;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Tap to drop a pin')),
        body: SafeArea(
          child: FlutterMap(
            options: mapOptions(onTap: (_, p) => setState(() => _pin = p)),
            children: [
              darkTiles,
              if (_pin != null)
                MarkerLayer(markers: [
                  Marker(point: _pin!, width: 40, height: 40, child: const Icon(Icons.location_on_outlined, size: 40, color: AppColors.accent)),
                ]),
              mapAttribution,
            ],
          ),
        ),
        floatingActionButton: _pin == null
            ? null
            : FloatingActionButton.extended(
                onPressed: () => Navigator.pop(context, _pin),
                icon: const Icon(Icons.check_outlined),
                label: const Text('Use this pin')),
      );
}
