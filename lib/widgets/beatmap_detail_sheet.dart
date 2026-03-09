import 'package:flutter/material.dart';
import '../models/osu_realm_models.dart';
import 'difficulty_tile.dart';

class BeatmapDetailSheet extends StatelessWidget {
  final List<BeatmapInfo> beatmaps;
  final String title;
  final String artist;

  const BeatmapDetailSheet({
    super.key,
    required this.beatmaps,
    required this.title,
    required this.artist,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...beatmaps]
      ..sort((a, b) => a.starRating.compareTo(b.starRating));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 1.0,
      maxChildSize: 1.0,
      builder: (_, ctrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(artist, style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: ctrl,
              itemCount: sorted.length,
              itemBuilder: (_, i) => DifficultyTile(beatmap: sorted[i]),
            ),
          ),
        ],
      ),
    );
  }
}
