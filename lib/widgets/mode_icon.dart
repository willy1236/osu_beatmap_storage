import 'package:flutter/material.dart';
import '../models/osu_realm_models.dart';

class ModeIcon extends StatelessWidget {
  final Iterable<BeatmapInfo> beatmaps;

  const ModeIcon({super.key, required this.beatmaps});

  @override
  Widget build(BuildContext context) {
    final modes = beatmaps.map((b) => b.ruleset?.shortName ?? '?').toSet();
    final label = modes.length == 1 ? modes.first : '♫';
    return CircleAvatar(
      radius: 18,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
