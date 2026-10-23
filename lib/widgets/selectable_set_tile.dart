import 'package:flutter/material.dart';

import '../models/beatmap_set_row.dart';
import 'beatmap_set_tile.dart';

/// 圖譜查看頁勾選模式的一列：左邊勾選框，右邊是原本的 [BeatmapSetTile]。
/// 沒有 OnlineID（<= 0）的圖譜不能勾選。
class SelectableSetTile extends StatelessWidget {
  const SelectableSetTile({
    super.key,
    required this.row,
    required this.selected,
    required this.onChanged,
  });

  final BeatmapSetRow row;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectable = row.onlineID > 0;
    return Row(
      children: [
        Tooltip(
          message: selectable ? '' : '沒有 OnlineID，無法推送',
          child: Checkbox(
            value: selected,
            onChanged: selectable ? (v) => onChanged(v == true) : null,
          ),
        ),
        Expanded(child: BeatmapSetTile(row: row)),
      ],
    );
  }
}
