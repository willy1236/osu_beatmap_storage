import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/osu_realm_models.dart';
import 'beatmap_detail_sheet.dart';
import 'download_button.dart';
import 'mode_icon.dart';

class BeatmapSetTile extends StatelessWidget {
  final BeatmapSetInfo set;

  const BeatmapSetTile({super.key, required this.set});

  @override
  Widget build(BuildContext context) {
    final meta = set.beatmaps.isNotEmpty ? set.beatmaps.first.metadata : null;
    final title = (meta?.titleUnicode?.isNotEmpty == true)
        ? meta!.titleUnicode!
        : (meta?.title ?? '（未知標題）');
    final artist = (meta?.artistUnicode?.isNotEmpty == true)
        ? meta!.artistUnicode!
        : (meta?.artist ?? '（未知藝術家）');

    final stars =
        set.beatmaps.map((b) => b.starRating).where((s) => s > 0).toList()
          ..sort();

    final statusText = kStatusLabel[set.status] ?? '?';

    final added = set.dateAdded.toLocal();
    final addedStr =
        '${added.year}/${added.month.toString().padLeft(2, '0')}/${added.day.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: ListTile(
        leading: ModeIcon(beatmaps: set.beatmaps),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '$artist  ·  $statusText  ·  ${set.beatmaps.length} 難度  ·  $addedStr',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            DownloadButton(onlineID: set.onlineID, title: title),
          ],
        ),
        onTap: () =>
            _showDetails(context, set.beatmaps.toList(), title, artist),
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
