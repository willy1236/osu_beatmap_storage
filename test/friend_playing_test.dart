import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/services/friend_service.dart';

import 'friend_test_helpers.dart';

void main() {
  late FakeFriendBackend be;

  setUp(() => be = FakeFriendBackend());

  Future<FriendService> make() async {
    final auth = makeAuth();
    await auth.init();
    final s = FriendService(api: be.api, auth: auth);
    await pumpEventQueue();
    return s;
  }

  test('好友列表解析 playing，缺欄位視為 false', () async {
    be.friends = [
      {...peerJson(bId, 'b', timeKey: 'since'), 'playing': true},
      peerJson(cId, 'c', timeKey: 'since'),
    ];
    final s = await make();
    expect(s.friends.map((p) => p.playing), [true, false]);
  });

  test('setPlaying：更新該好友、通知一次；大小寫不分；非好友或沒變不通知', () async {
    be.friends = [peerJson(bId, 'b', timeKey: 'since')];
    final s = await make();
    var n = 0;
    s.addListener(() => n++);
    s.setPlaying(bId.toUpperCase(), true);
    expect(s.friends.single.playing, isTrue);
    expect(s.friends.single.username, 'b');
    expect(n, 1);
    s.setPlaying(bId, true);
    s.setPlaying(cId, true);
    expect(n, 1);
    s.setPlaying(bId, false);
    expect(s.friends.single.playing, isFalse);
    expect(n, 2);
  });
}
