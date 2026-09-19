import 'package:flutter/material.dart';

import 'panel.dart';

class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.eyebrow, required this.title, this.trailing});
  final String eyebrow, title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Eyebrow(eyebrow),
            const SizedBox(height: 2),
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
          ]),
        ),
        ?trailing,
      ]);
}
