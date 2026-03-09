import 'dart:io';
import 'package:flutter/material.dart';

class CsvPickerDialog extends StatelessWidget {
  final List<File> files;

  const CsvPickerDialog({super.key, required this.files});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('選擇 CSV 檔案'),
      content: SizedBox(
        width: 480,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: files.length,
          itemBuilder: (_, i) {
            final name = files[i].uri.pathSegments.last;
            return ListTile(
              leading: const Icon(Icons.table_chart),
              title: Text(name),
              onTap: () => Navigator.pop(context, files[i]),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
