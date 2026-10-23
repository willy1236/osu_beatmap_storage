import 'package:flutter/material.dart';

/// 最上層的 route 是不是對話框或彈出選單（[PopupRoute]）。
/// 用 popUntil 只看最上層、立刻停下，不會真的 pop 任何 route
bool topRouteIsPopup(NavigatorState navigator) {
  var popup = false;
  navigator.popUntil((route) {
    popup = route is PopupRoute;
    return true;
  });
  return popup;
}
