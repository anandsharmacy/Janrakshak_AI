import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum Severity {
  low('Low', AppColors.statusOk),
  moderate('Moderate', AppColors.statusModerate),
  high('High', AppColors.statusHigh),
  critical('Critical', AppColors.statusCritical);

  const Severity(this.label, this.color);
  final String label;
  final Color color;
}

enum ReportSource {
  fieldOfficer('Field Officer verified', Icons.verified_outlined),
  community('Community reported', Icons.groups_outlined),
  automated('Automated advisory', Icons.sensors_outlined);

  const ReportSource(this.label, this.icon);
  final String label;
  final IconData icon;
}

const incidentIcons = <String, IconData>{
  'Cyclones': Icons.cyclone_outlined,
  'Floods': Icons.flood_outlined,
  'Landslides': Icons.landslide_outlined,
  'Forest Fires': Icons.local_fire_department_outlined,
  'Tsunami': Icons.tsunami_outlined,
  'Earthquakes': Icons.vibration_outlined,
  'Dust Storms': Icons.air_outlined,
  'Rain Storms': Icons.thunderstorm_outlined,
  'Snow Storms': Icons.ac_unit_outlined,
  'Infrastructure Damage': Icons.construction_outlined,
};

IconData incidentIcon(String type) => incidentIcons[type] ?? Icons.warning_amber_outlined;
