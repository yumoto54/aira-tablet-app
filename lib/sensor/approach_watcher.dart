import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';

/// 人数センサー(AIカメラ)の「近づいた人がいる」を、バックエンドに2秒ごとに確かめる。
/// 映像は扱わない。サーバーから受け取るのは「近づいた回数の通し番号」だけ。
///
/// 起動した直後の1回目は、過去の「近づいた」で声をかけないよう、番号を覚えるだけにする。
/// 通信に失敗しても何もせず、次の確認に進む(会話の機能には影響させない)。
class ApproachWatcher {
  ApproachWatcher({required this.onApproach, http.Client? client}) : _client = client ?? http.Client();

  /// 前回の確認より番号が増えたときに呼ばれる。
  /// 声をかけてよいか(会話中でないか・間隔)の判断は、呼ばれた側で行う。
  final void Function() onApproach;
  final http.Client _client;

  Timer? _timer;
  int? _lastSeq;
  bool _busy = false;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _client.close();
  }

  Future<void> _poll() async {
    if (_busy) return;
    _busy = true;
    try {
      final response = await _client.get(
        Uri.parse('$kApiBaseUrl/api/sensor/latest'),
        headers: {
          'x-functions-key': kApiFunctionKey,
          if (kTenantId.isNotEmpty) 'x-tenant-id': kTenantId,
        },
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return;
      final seq = ((jsonDecode(response.body) as Map<String, dynamic>)['approachSeq'] as num?)?.toInt();
      if (seq == null) return;
      final last = _lastSeq;
      _lastSeq = seq;
      if (last != null && seq > last) onApproach();
    } catch (_) {
      // 通信できないときは黙って次の確認を待つ
    } finally {
      _busy = false;
    }
  }
}
