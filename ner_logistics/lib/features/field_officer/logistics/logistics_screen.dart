import 'package:flutter/material.dart';
import '../../../mock_data/models.dart';
import '../../../mock_data/mock_shipments.dart';
import '../../../shared/widgets/risk_badge.dart';
import '../../../theme/colors.dart';
import '../../../theme/text_styles.dart';

class LogisticsScreen extends StatefulWidget {
  const LogisticsScreen({super.key});

  @override
  State<LogisticsScreen> createState() => _LogisticsScreenState();
}

class _LogisticsScreenState extends State<LogisticsScreen> {
  String? selectedId;

  @override
  Widget build(BuildContext context) {
    final selected = selectedId != null
        ? mockShipments.where((s) => s.id == selectedId).firstOrNull
        : null;

    if (selected != null) {
      return ShipmentDetailView(
        shipment: selected,
        onBack: () => setState(() => selectedId = null),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: AppColors.ink.withValues(alpha: 0.10),
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                '4 active shipments \u00b7 Ri Bhoi district',
                style: TextStyle(
                  fontFamily: 'PublicSans',
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.ink.withValues(alpha: 0.60),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                for (int i = 0; i < mockShipments.length; i++) ...[
                  ShipmentCard(
                    shipment: mockShipments[i],
                    onTap: () => setState(() => selectedId = mockShipments[i].id),
                  ),
                  if (i != mockShipments.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusCfg {
  final String label;
  final Color bg;
  final Color border;
  final Color fg;
  const _StatusCfg({
    required this.label,
    required this.bg,
    required this.border,
    required this.fg,
  });
}

_StatusCfg _statusChip(ShipmentStatus status) {
  switch (status) {
    case ShipmentStatus.delayed:
      return _StatusCfg(
        label: 'Delayed',
        bg: AppColors.criticalBg,
        border: AppColors.signalRed700.withValues(alpha: 0.30),
        fg: AppColors.signalRed700,
      );
    case ShipmentStatus.onSchedule:
      return _StatusCfg(
        label: 'On schedule',
        bg: AppColors.clearBg,
        border: AppColors.deepGreen700.withValues(alpha: 0.30),
        fg: AppColors.deepGreen700,
      );
    case ShipmentStatus.inTransit:
      return _StatusCfg(
        label: 'In transit',
        bg: AppColors.navyTint,
        border: AppColors.navy900.withValues(alpha: 0.20),
        fg: AppColors.navy900,
      );
  }
}

class ShipmentCard extends StatelessWidget {
  final Shipment shipment;
  final VoidCallback onTap;

  const ShipmentCard({
    super.key,
    required this.shipment,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusCfg = _statusChip(shipment.status);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.ink.withValues(alpha: 0.20),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  shipment.id,
                  style: const TextStyle(
                    fontFamily: 'PublicSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy900,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  shipment.vehicleId,
                  style: const TextStyle(
                    fontFamily: 'PublicSans',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.ink,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusCfg.bg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: statusCfg.border),
                  ),
                  child: Text(
                    statusCfg.label,
                    style: AppTextStyles.chipLabel
                        .copyWith(color: statusCfg.fg),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 16,
                  color: AppColors.navy900,
                ),
                const SizedBox(width: 6),
                Text(
                  shipment.cargoType,
                  style: const TextStyle(
                    fontFamily: 'PublicSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${shipment.origin} \u2192 ${shipment.destination}',
              style: const TextStyle(
                fontFamily: 'PublicSans',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: AppColors.ink,
                ),
                const SizedBox(width: 4),
                Text(
                  shipment.currentLocation,
                  style: const TextStyle(
                    fontFamily: 'PublicSans',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.access_time_outlined,
                  size: 14,
                  color: AppColors.ink,
                ),
                const SizedBox(width: 4),
                Text(
                  'ETA ${shipment.eta}',
                  style: const TextStyle(
                    fontFamily: 'PublicSans',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                RiskBadge(level: shipment.risk, compact: true),
                if (shipment.delay != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 13,
                    color: AppColors.saffronDark,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    shipment.delay!,
                    style: TextStyle(
                      fontFamily: 'PublicSans',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.saffronDark,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ShipmentDetailView extends StatelessWidget {
  final Shipment shipment;
  final VoidCallback onBack;

  const ShipmentDetailView({
    super.key,
    required this.shipment,
    required this.onBack,
  });

  String _timestampFor(ShipmentStatus status) {
    switch (status) {
      case ShipmentStatus.delayed:
        return '09:41 today';
      case ShipmentStatus.onSchedule:
        return '09:40 today';
      case ShipmentStatus.inTransit:
        return '09:38 today';
    }
  }

  String _noteFor(Shipment shipment) {
    switch (shipment.status) {
      case ShipmentStatus.delayed:
        return 'Vehicle halted \u2014 ${shipment.delay}. Rerouting via Lumshnong Bypass in progress.';
      case ShipmentStatus.onSchedule:
        return 'Vehicle on track. No incidents on current route segment.';
      case ShipmentStatus.inTransit:
        return 'Vehicle moving normally. Monitor route conditions.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusCfg = _statusChip(shipment.status);

    return Column(
      children: [
        InkWell(
          onTap: onBack,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.chevron_left,
                  size: 20,
                  color: AppColors.navy900,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Logistics',
                  style: TextStyle(
                    fontFamily: 'PublicSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy900,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shipment.id,
                            style: const TextStyle(
                              fontFamily: 'PublicSans',
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navy900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            shipment.vehicleId,
                            style: const TextStyle(
                              fontFamily: 'PublicSans',
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusCfg.bg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: statusCfg.border),
                      ),
                      child: Text(
                        statusCfg.label,
                        style: AppTextStyles.chipLabel
                            .copyWith(color: statusCfg.fg),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  shipment.cargoType,
                  style: const TextStyle(
                    fontFamily: 'PublicSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy900,
                  ),
                ),
                if (shipment.delay != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.saffronBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppColors.saffron600.withValues(alpha: 0.30)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_outlined,
                          size: 16,
                          color: AppColors.saffronDark,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Delay: ${shipment.delay!}',
                            style: TextStyle(
                              fontFamily: 'PublicSans',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.saffronDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppColors.ink.withValues(alpha: 0.20)),
                  ),
                  child: Column(
                    children: [
                      _gridRow(
                        'Current Location',
                        shipment.currentLocation,
                        'Route',
                        shipment.route,
                        true,
                      ),
                      _gridRow(
                        'Origin',
                        shipment.origin,
                        'Destination',
                        shipment.destination,
                        true,
                      ),
                      _gridRow(
                        'ETA',
                        shipment.eta,
                        'Vehicle',
                        shipment.vehicleId,
                        false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Route risk:',
                      style: TextStyle(
                        fontFamily: 'PublicSans',
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(width: 8),
                    RiskBadge(level: shipment.risk),
                  ],
                ),
                if (shipment.risk == RiskLevel.critical) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.criticalBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppColors.signalRed700.withValues(alpha: 0.30)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.warning_outlined,
                            size: 16,
                            color: AppColors.signalRed700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'SH-5 Km 31\u201334 blocked \u2014 rerouting advised',
                            style: TextStyle(
                              fontFamily: 'PublicSans',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.signalRed700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppColors.ink.withValues(alpha: 0.20)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LATEST UPDATE',
                        style: TextStyle(
                          fontFamily: 'PublicSans',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.88,
                          color: AppColors.ink.withValues(alpha: 0.60),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _timestampFor(shipment.status),
                        style: const TextStyle(
                          fontFamily: 'PublicSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _noteFor(shipment),
                        style: const TextStyle(
                          fontFamily: 'NotoSans',
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: AppColors.ink,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _gridRow(
    String leftLabel,
    String leftValue,
    String rightLabel,
    String rightValue,
    bool hasBottomBorder,
  ) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: AppColors.ink.withValues(alpha: 0.20),
                  ),
                  bottom: BorderSide(
                    color: hasBottomBorder
                        ? AppColors.ink.withValues(alpha: 0.20)
                        : Colors.transparent,
                  ),
                ),
              ),
              child: _gridCell(leftLabel, leftValue),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: hasBottomBorder
                        ? AppColors.ink.withValues(alpha: 0.20)
                        : Colors.transparent,
                  ),
                ),
              ),
              child: _gridCell(rightLabel, rightValue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridCell(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: 'PublicSans',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.88,
            color: AppColors.ink.withValues(alpha: 0.60),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'PublicSans',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.navy900,
          ),
        ),
      ],
    );
  }
}
