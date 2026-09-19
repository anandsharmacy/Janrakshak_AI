import '../core/demo/demo_mode.dart';
import 'models.dart';

final List<AppAlert> _demoAlerts = [
  const AppAlert(
    id: 'ALT-001',
    severity: AlertSeverity.critical,
    title: 'NH-6 Km 31–34 high risk — landslide predicted',
    description:
        'ML model confidence 78%. Predicted landslide event within 11 min. '
        'Current route passes through flagged segment.',
    distance: '5 km ahead',
    time: '09:41',
    recommendedAction:
        'Avoid Km 31–34 immediately. Take Lumshnong bypass. Notify control room.',
    incidentId: 'INC-2291',
  ),
  const AppAlert(
    id: 'ALT-002',
    severity: AlertSeverity.high,
    title: 'SH-5 Km 31–34 full blockage — vehicle unable to pass',
    description:
        'Construction lorry AS-07-TR-0091 blocked at Km 31. Road cleared '
        'partially. Single-lane movement only.',
    distance: '6.2 km',
    time: '09:28',
    recommendedAction:
        'Coordinate with logistics officer. Dispatch field team for clearance.',
    incidentId: 'INC-2287',
  ),
  const AppAlert(
    id: 'ALT-003',
    severity: AlertSeverity.high,
    title: 'Flood warning — Umiam river level rising',
    description:
        'Water level at 4.8m, monitoring threshold is 5.0m. Risk of overflow '
        'near Umiam bridge within 2h.',
    distance: '12 km',
    time: '09:15',
    recommendedAction:
        'Monitor every 30 min. Alert district coordinator if level reaches 5m.',
    incidentId: 'INC-2280',
  ),
  const AppAlert(
    id: 'ALT-004',
    severity: AlertSeverity.moderate,
    title: 'NH-6 Km 22–26 wet slope — reduced speed advisory',
    description:
        'Rainfall has caused surface runoff on NH-6. Traction reduced. '
        'No blockage currently.',
    distance: '4 km',
    time: '08:52',
    recommendedAction: 'Reduce speed to 30 km/h. Avoid overtaking on slope section.',
  ),
  const AppAlert(
    id: 'ALT-005',
    severity: AlertSeverity.moderate,
    title: 'LOG-4451 convoy delayed — rerouting in progress',
    description:
        'Shipment of construction material from Lumding delayed 2h 15m due '
        'to SH-5 blockage. Rerouting via bypass.',
    distance: 'Field update',
    time: '09:30',
    recommendedAction:
        'Update receiving station at Umiam. Confirm new ETA with logistics control.',
  ),
  const AppAlert(
    id: 'ALT-006',
    severity: AlertSeverity.info,
    title: 'Daily sync complete — all field reports uploaded',
    description:
        '3 incident reports, 2 task completions, and 1 route inspection '
        'synced to district server at 09:38.',
    distance: 'System',
    time: '09:38',
    recommendedAction: 'No action required.',
  ),
  const AppAlert(
    id: 'ALT-007',
    severity: AlertSeverity.info,
    title: 'Weather update — heavy rain forecast Ri Bhoi',
    description:
        'IMD forecast: 80–120mm rainfall expected in next 6h. Elevated '
        'landslide risk in hilly terrain.',
    distance: 'District',
    time: '09:00',
    recommendedAction: 'Heighten vigilance on NH-6 and SH-5 hill sections.',
  ),
];

/// The sample data while demo mode is on, otherwise empty.
List<AppAlert> get mockAlerts => DemoMode.enabled ? _demoAlerts : const [];
