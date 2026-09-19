import '../core/demo/demo_mode.dart';
import 'models.dart';

const List<FleetVehicle> _demoFleet = [
  FleetVehicle(id: 'TRK-1042', route: 'NH-29', destination: 'Kohima', statusLabel: 'Delayed', risk: Priority.high, eta: '+2h'),
  FleetVehicle(id: 'TRK-1088', route: 'NH-2', destination: 'Kohima', statusLabel: 'At risk', risk: Priority.critical, eta: '—'),
  FleetVehicle(id: 'TRK-1015', route: 'NH-29', destination: 'Dimapur', statusLabel: 'Moving', risk: Priority.low, eta: '16:05'),
  FleetVehicle(id: 'TRK-0994', route: 'NH-39', destination: 'Chumukedima', statusLabel: 'Moving', risk: Priority.low, eta: '11:20'),
  FleetVehicle(id: 'LG-102', route: 'NH-2', destination: 'Kohima', statusLabel: 'At Risk', risk: Priority.high, eta: '4:40 PM'),
  FleetVehicle(id: 'LG-115', route: 'NH-27', destination: 'Tezpur', statusLabel: 'Stopped', risk: Priority.critical, eta: 'Suspended'),
  FleetVehicle(id: 'LG-089', route: 'NH-13', destination: 'Itanagar', statusLabel: 'Stopped', risk: Priority.critical, eta: 'Suspended'),
  FleetVehicle(id: 'LG-134', route: 'NH-40', destination: 'Shillong', statusLabel: 'On Time', risk: Priority.low, eta: '2:15 PM'),
];

/// The sample data while demo mode is on, otherwise empty.
List<FleetVehicle> get mockFleet => DemoMode.enabled ? _demoFleet : const [];
