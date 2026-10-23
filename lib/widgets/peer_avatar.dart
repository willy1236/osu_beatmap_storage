import 'package:flutter/material.dart';

/// 好友頁用的圓形頭像；沒有圖片（或載入失敗）時用預設圖示
class PeerAvatar extends StatelessWidget {
  const PeerAvatar({super.key, this.picture, this.radius = 20});

  final String? picture;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(Icons.person, size: radius * 1.2);
    final url = picture;
    if (url == null || url.isEmpty) {
      return CircleAvatar(radius: radius, child: icon);
    }
    return CircleAvatar(
      radius: radius,
      backgroundImage: NetworkImage(url),
      onBackgroundImageError: (_, _) {},
      child: null,
    );
  }
}
