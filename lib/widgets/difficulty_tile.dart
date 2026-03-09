import 'package:flutter/material.dart';
import '../models/osu_realm_models.dart';

class DifficultyTile extends StatelessWidget {
  final BeatmapInfo beatmap;

  const DifficultyTile({super.key, required this.beatmap});

  String _formatDuration(double ms) {
    final s = (ms / 1000).round();
    final m = s ~/ 60;
    return '${m}m ${s % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    final mode = beatmap.ruleset?.shortName ?? '?';
    return ListTile(
      leading: Text(
        '★${beatmap.starRating.toStringAsFixed(2)}',
        style: const TextStyle(color: Colors.amber, fontSize: 12),
      ),
      title: Text(beatmap.difficultyName ?? '（未命名）'),
      subtitle: Text(
        '[$mode]  BPM ${beatmap.bpm.toStringAsFixed(0)}'
        '  ${_formatDuration(beatmap.length)}',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}
