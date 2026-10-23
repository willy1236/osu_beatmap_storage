import 'package:flutter/material.dart';
import '../models/beatmap_set_row.dart';
import '../models/osu_realm_models.dart';
import 'beatmap_detail_sheet.dart';
import 'cloud_presence_badge.dart';
import 'download_button.dart';
import 'mode_icon.dart';
import 'open_web_button.dart';

class BeatmapSetTile extends StatelessWidget {
  final BeatmapSetRow row;

  const BeatmapSetTile({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final stars = row.stars;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: ListTile(
        leading: ModeIcon(label: row.modeLabel),
        title: Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${row.artist}  ·  ${row.statusText}  ·  ${row.difficultyCount} 難度  ·  ${row.addedStr}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CloudPresenceBadge(onlineID: row.onlineID),
            if (stars.isNotEmpty)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '★ ${stars.last.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (stars.length > 1)
                    Text(
                      '${stars.first.toStringAsFixed(2)} – ${stars.last.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.grey[400], fontSize: 10),
                    ),
                ],
              ),
            OpenWebButton(onlineID: row.onlineID),
            DownloadButton(onlineID: row.onlineID, title: row.title),
          ],
        ),
        onTap: () => _showDetails(
          context,
          row.set.beatmaps.toList(),
          row.title,
          row.artist,
        ),
      ),
    );
  }

  void _showDetails(
    BuildContext context,
    List<BeatmapInfo> beatmaps,
    String title,
    String artist,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (_) =>
          BeatmapDetailSheet(beatmaps: beatmaps, title: title, artist: artist),
    );
  }
}
