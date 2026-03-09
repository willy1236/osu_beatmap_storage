import 'package:flutter/material.dart';
import '../models/csv_row.dart';
import 'download_button.dart';

class CsvRowTile extends StatelessWidget {
  final CsvRow row;

  const CsvRowTile({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final title = row['TitleUnicode'].isNotEmpty
        ? row['TitleUnicode']
        : row['Title'].isNotEmpty
        ? row['Title']
        : '（未知標題）';
    final artist = row['ArtistUnicode'].isNotEmpty
        ? row['ArtistUnicode']
        : row['Artist'].isNotEmpty
        ? row['Artist']
        : '（未知藝術家）';
    final mode = row['模式'];
    final status = row['Status'];
    final diffCount = row['難度數'];
    final starLow = row['最低星數'];
    final starHigh = row['最高星數'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            mode.isNotEmpty ? mode : '♫',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '$artist  ·  $status  ·  $diffCount 難度',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (starHigh.isNotEmpty)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '★ $starHigh',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (starLow != starHigh)
                    Text(
                      '$starLow – $starHigh',
                      style: TextStyle(color: Colors.grey[400], fontSize: 10),
                    ),
                ],
              ),
            DownloadButton(
              onlineID: int.tryParse(row['OnlineID']) ?? 0,
              title: row['TitleUnicode'].isNotEmpty
                  ? row['TitleUnicode']
                  : row['Title'],
            ),
          ],
        ),
        onTap: () => showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (artist != '（未知藝術家）') Text('藝術家：$artist'),
                if (row['Creator'].isNotEmpty) Text('製圖者：${row['Creator']}'),
                Text('狀態：$status'),
                Text('難度數：$diffCount'),
                if (mode.isNotEmpty) Text('模式：$mode'),
                if (row['BPM'].isNotEmpty) Text('BPM：${row['BPM']}'),
                if (starHigh.isNotEmpty) Text('星數：$starLow – $starHigh'),
                if (row['OnlineID'].isNotEmpty && row['OnlineID'] != '0')
                  Text('Online ID：${row['OnlineID']}'),
                if (row['加入日期'].isNotEmpty) Text('加入日期：${row['加入日期']}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('關閉'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
