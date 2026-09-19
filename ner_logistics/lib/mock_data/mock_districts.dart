import 'models.dart';

const List<DistrictSummary> mockDistricts = [
  DistrictSummary(name: 'Dimapur', state: 'Nagaland', risk: Priority.critical, accessScore: 81, incidentCount: 6, criticalCount: 3, blockedRoutes: 4, logisticsNote: '6 delayed', statusLabel: 'On alert'),
  DistrictSummary(name: 'Kohima', state: 'Nagaland', risk: Priority.critical, accessScore: 74, incidentCount: 3, criticalCount: 2, blockedRoutes: 2, logisticsNote: '2 held', statusLabel: 'On alert'),
  DistrictSummary(name: 'Kamrup', state: 'Assam', risk: Priority.high, accessScore: 58, incidentCount: 4, criticalCount: 0, blockedRoutes: 1, logisticsNote: '1 delayed', statusLabel: 'Monitoring'),
  DistrictSummary(name: 'Ri Bhoi', state: 'Meghalaya', risk: Priority.high, accessScore: 63, incidentCount: 3, criticalCount: 1, blockedRoutes: 2, logisticsNote: '3 delayed', statusLabel: 'Monitoring'),
  DistrictSummary(name: 'Papum Pare', state: 'Arunachal Pr.', risk: Priority.medium, accessScore: 39, incidentCount: 1, criticalCount: 0, blockedRoutes: 0, logisticsNote: 'On time', statusLabel: 'Stable'),
  DistrictSummary(name: 'Imphal West', state: 'Manipur', risk: Priority.low, accessScore: 21, incidentCount: 0, criticalCount: 0, blockedRoutes: 0, logisticsNote: 'On time', statusLabel: 'Stable'),
  DistrictSummary(name: 'Aizawl', state: 'Mizoram', risk: Priority.medium, accessScore: 44, incidentCount: 1, criticalCount: 0, blockedRoutes: 1, logisticsNote: '1 delayed', statusLabel: 'Monitoring'),
  DistrictSummary(name: 'East Sikkim', state: 'Sikkim', risk: Priority.low, accessScore: 18, incidentCount: 0, criticalCount: 0, blockedRoutes: 0, logisticsNote: 'On time', statusLabel: 'Stable'),
  DistrictSummary(name: 'Barpeta', state: 'Assam', risk: Priority.critical, accessScore: 77, incidentCount: 5, criticalCount: 2, blockedRoutes: 3, logisticsNote: '5 delayed', statusLabel: 'On alert'),
  DistrictSummary(name: 'Tawang', state: 'Arunachal Pr.', risk: Priority.high, accessScore: 69, incidentCount: 2, criticalCount: 1, blockedRoutes: 1, logisticsNote: '1 held', statusLabel: 'Monitoring'),
  DistrictSummary(name: 'Cachar', state: 'Assam', risk: Priority.medium, accessScore: 47, incidentCount: 2, criticalCount: 0, blockedRoutes: 1, logisticsNote: '2 delayed', statusLabel: 'Monitoring'),
  DistrictSummary(name: 'West Jaintia', state: 'Meghalaya', risk: Priority.low, accessScore: 24, incidentCount: 1, criticalCount: 0, blockedRoutes: 0, logisticsNote: 'On time', statusLabel: 'Stable'),
];
