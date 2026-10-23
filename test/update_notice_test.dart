import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/services/update_service.dart';
import 'package:osu_beatmap_storage/widgets/update_button.dart';

void main() {
  testWidgets('上次更新留下 log：顯示一次提示，不重複跳', (tester) async {
    final dir = Directory.systemTemp.createTempSync('notice');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/update_error.log').writeAsStringSync('some failure');

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UpdateButton())),
    );
    await tester.runAsync(
      () => UpdateService.instance.loadLastUpdateLog(appDir: dir),
    );
    await tester.pumpAndSettle();
    expect(find.text('上次更新沒有順利完成'), findsOneWidget);
    expect(find.textContaining('some failure'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('上次更新沒有順利完成'), findsNothing);
    expect(UpdateService.instance.pendingNotice, isNull);
  });
}
