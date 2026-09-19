import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/seed_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'contacts_repo.dart';

class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranked = ref.watch(rankedContactsProvider);
    final district = ref.watch(districtFilterProvider);
    final hasGps = ref.watch(positionProvider).value != null;
    final districts = ref.watch(contactsProvider).value?.map((c) => c.district).toSet().toList() ?? [];
    districts.sort();

    void snack(bool ok, String what) {
      if (!ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't open $what on this device.")));
    }

    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const ScreenHeader(eyebrow: 'Emergency', title: 'Contacts'),
        const SizedBox(height: 16),
        PillButton(
          label: 'SOS - Call 112',
          icon: Icons.phone_in_talk_outlined,
          color: AppColors.statusCritical,
          expand: true,
          onPressed: () async => snack(await callNumber('112'), 'the dialer'),
        ),
        const SizedBox(height: 4),
        Text('Opens your dialer with 112 (national emergency number).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mutedOnDark)),
        const SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          key: ValueKey(district),
          initialValue: district,
          isExpanded: true,
          dropdownColor: AppColors.bgRaised,
          decoration: const InputDecoration(labelText: 'Filter by district'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('All districts')),
            for (final d in districts) DropdownMenuItem<String?>(value: d, child: Text(d)),
          ],
          onChanged: ref.read(districtFilterProvider.notifier).set,
        ),
        const SizedBox(height: 12),
        if (kSampleData)
          const StatusBanner(lead: 'Sample directory.', text: 'Listed helplines are real (1077, 108, 100); station locations are illustrative.'),
        if (!hasGps)
          const Padding(
              padding: EdgeInsets.only(top: 8),
              child: StatusBanner(lead: 'Location off.', text: 'Listing alphabetically instead of nearest first.')),
        const SizedBox(height: 12),
        ...ranked.when(
          loading: () => [const Center(child: CircularProgressIndicator())],
          error: (e, _) => [StatusBanner(lead: 'Directory unavailable.', text: '$e', color: AppColors.statusCritical, icon: Icons.error_outline)],
          data: (list) => [
            for (final kind in ContactKind.values) ...[
              Padding(padding: const EdgeInsets.only(top: 8, bottom: 8), child: Eyebrow(kind.label)),
              if (list.every((r) => r.contact.kind != kind)) const Text('None in this district.'),
              for (final r in list.where((r) => r.contact.kind == kind))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LightCard(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    child: Builder(builder: (context) {
                      final t = Theme.of(context).textTheme;
                      return Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.contact.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                                '${r.contact.district}, ${r.contact.state}${r.km == null ? '' : ' · ${r.km!.toStringAsFixed(r.km! < 10 ? 1 : 0)} km'}',
                                style: t.bodySmall),
                          ]),
                        ),
                        IconButton(
                          tooltip: 'Call ${r.contact.name}',
                          icon: const Icon(Icons.call_outlined),
                          onPressed: () async => snack(await callNumber(r.contact.phone), 'the dialer'),
                        ),
                        if (kind != ContactKind.fieldOfficer)
                          IconButton(
                            tooltip: 'Navigate to ${r.contact.name}',
                            icon: const Icon(Icons.directions_outlined),
                            onPressed: () async => snack(await navigateTo(r.contact.pos), 'maps'),
                          ),
                      ]);
                    }),
                  ),
                ),
            ],
          ],
        ),
      ]),
    );
  }
}
