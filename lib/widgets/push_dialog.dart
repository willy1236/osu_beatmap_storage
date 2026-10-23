import 'package:flutter/material.dart';

import '../models/cloud_entry.dart';
import '../services/friend_service.dart';
import '../services/push_service.dart';
import 'peer_avatar.dart';

/// 開啟「推送給好友」對話框；送出成功回傳 true。
/// [service]、[friends] 供測試注入，預設用單例。
Future<bool> showPushDialog(
  BuildContext context, {
  required List<CloudEntry> entries,
  PushService? service,
  FriendService? friends,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => PushDialog(
      entries: entries,
      service: service ?? PushService.instance,
      friends: friends ?? FriendService.instance,
    ),
  );
  return ok == true;
}

/// 推送對話框：多選好友、附言、送出。張數或附言超過上限時送出鈕停用並顯示原因
class PushDialog extends StatefulWidget {
  const PushDialog({
    super.key,
    required this.entries,
    required this.service,
    required this.friends,
  });

  final List<CloudEntry> entries;
  final PushService service;
  final FriendService friends;

  @override
  State<PushDialog> createState() => _PushDialogState();
}

class _PushDialogState extends State<PushDialog> {
  final _message = TextEditingController();
  final Set<String> _selected = {};
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  /// 不能送出的原因；可以送出時為 null
  String? get _blockReason {
    if (widget.entries.isEmpty) return '請先勾選要推送的圖譜';
    if (widget.entries.length > kPushEntriesMax) {
      return '一次最多推送 $kPushEntriesMax 張，目前勾選 ${widget.entries.length} 張';
    }
    if (_message.text.length > kPushMessageMax) {
      return '附言最多 $kPushMessageMax 字，目前 ${_message.text.length} 字';
    }
    if (_selected.isEmpty) return '請選擇至少一位好友';
    return null;
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    final r = await widget.service.send(
      toAccountIds: _selected.toList(),
      message: _message.text,
      entries: widget.entries,
    );
    if (!mounted) return;
    if (r.ok) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已推送 ${widget.entries.length} 個圖譜集給 ${_selected.length} 位好友',
          ),
        ),
      );
      return;
    }
    setState(() {
      _sending = false;
      _error = r.message ?? '推送失敗';
    });
    // 有人已不是好友：重讀好友列表，讓清單反映現況
    if (r.status == PushSendStatus.notFriend) widget.friends.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _blockReason;
    return AlertDialog(
      title: Text('推送給好友（${widget.entries.length} 個圖譜集）'),
      content: SizedBox(
        width: 420,
        child: ListenableBuilder(
          listenable: widget.friends,
          builder: (context, _) {
            final friends = widget.friends.friends;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (friends.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('還沒有好友可以推送'),
                  )
                else
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final p in friends)
                            CheckboxListTile(
                              dense: true,
                              value: _selected.contains(p.accountId),
                              onChanged: _sending
                                  ? null
                                  : (v) => setState(() {
                                      if (v == true) {
                                        _selected.add(p.accountId);
                                      } else {
                                        _selected.remove(p.accountId);
                                      }
                                    }),
                              secondary: PeerAvatar(
                                picture: p.picture,
                                radius: 14,
                              ),
                              title: Text(p.displayName),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _message,
                  enabled: !_sending,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: '附言（選填）',
                    border: const OutlineInputBorder(),
                    counterText: '${_message.text.length}/$kPushMessageMax',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (reason != null && !_sending)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      reason,
                      style: const TextStyle(color: Colors.orange),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: reason != null || _sending ? null : _send,
          child: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('送出'),
        ),
      ],
    );
  }
}

/// AppBar 上的「推送給好友」按鈕；[entries] 為空時停用
class PushButton extends StatelessWidget {
  const PushButton({super.key, required this.entries, this.onSent});

  final List<CloudEntry> entries;
  final VoidCallback? onSent;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.send),
      tooltip: '推送給好友（${entries.length}）',
      onPressed: entries.isEmpty
          ? null
          : () async {
              final sent = await showPushDialog(context, entries: entries);
              if (sent) onSent?.call();
            },
    );
  }
}
