import 'package:flutter/material.dart';

/// 圖示右上角的未處理數量紅點；[count] 為 0 時不顯示，超過 99 顯示 `99+`
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) => Badge(
    isLabelVisible: count > 0,
    label: Text(count > 99 ? '99+' : '$count'),
    child: child,
  );
}
