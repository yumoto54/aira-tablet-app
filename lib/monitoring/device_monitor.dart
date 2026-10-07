import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';

/// タブレットの稼働状況を、一定間隔でバックエンド(/api/heartbeat)に知らせる。
///
/// ダッシュボードに「どのタブレットが止まっているか」を出すためのもの。
/// 会話を止めないことが最優先なので、送信の失敗・端末情報の取得失敗は
/// すべて握りつぶす(画面にもエラーを出さない)。
class DeviceMonitor {
  DeviceMonitor._();

  static final DeviceMonitor instance = DeviceMonitor._();

  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();

  Timer? _timer;
  bool _sending = false;

  /// 今のアプリの状態名(idle / recording / sending / speaking)を返す関数。
  /// 画面側が登録する。状態の変更箇所ごとに通知を足さずに済むようにしている。
  String Function()? stateProvider;

  int _sttFailures = 0;
  int _apiFailures = 0;
  String? _lastError;
  DateTime? _lastConversationAt;

  /// 定期送信を始める。すぐに1回送り、以後は kHeartbeatInterval ごとに送る。
  void start() {
    if (_timer != null) return;
    unawaited(_sendHeartbeat());
    _timer = Timer.periodic(
      kHeartbeatInterval,
      (_) => unawaited(_sendHeartbeat()),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    stateProvider = null;
  }

  void recordSttFailure(String message) {
    _sttFailures++;
    _lastError = _stamp('STT: $message');
  }

  void recordApiFailure(String message) {
    _apiFailures++;
    _lastError = _stamp('API: $message');
  }

  void recordConversation() {
    _lastConversationAt = DateTime.now().toUtc();
  }

  /// 「いつのエラーか」が分かるように、時刻(UTC、秒まで)を頭に付ける。
  String _stamp(String message) {
    final iso = DateTime.now().toUtc().toIso8601String();
    return '[${iso.substring(0, 19)}Z] $message';
  }

  Future<String> _readNetwork() async {
    try {
      // connectivity_plus はバージョンによって単一値 / リストの両方がありうるので、
      // どちらが返ってきても扱えるようにしている。
      final dynamic result = await _connectivity.checkConnectivity();
      final List<dynamic> results = result is List ? result : [result];
      final names = results.map((r) => r.toString().split('.').last).toList();

      if (names.contains('wifi')) return 'wifi';
      if (names.contains('ethernet')) return 'ethernet';
      if (names.contains('mobile')) return 'mobile';
      if (names.isEmpty || names.every((n) => n == 'none')) return 'none';
      return 'other';
    } catch (_) {
      return 'other';
    }
  }

  Future<Map<String, dynamic>> _buildPayload() async {
    int? batteryLevel;
    bool? charging;

    try {
      final level = await _battery.batteryLevel;
      if (level >= 0 && level <= 100) batteryLevel = level;
    } catch (_) {}

    try {
      final state = await _battery.batteryState;
      // 電源につながっている状態(充電中・満充電・つないでいるが充電していない)を
      // まとめて「充電中」として扱う。バッテリー低下の警告は、電源が無いときだけ出したいため。
      charging = state == BatteryState.charging ||
          state == BatteryState.full ||
          state == BatteryState.connectedNotCharging;
    } catch (_) {}

    return {
      'deviceId': kDeviceId,
      'appVersion': kAppVersion,
      'appState': stateProvider?.call(),
      'batteryLevel': batteryLevel,
      'charging': charging,
      'network': await _readNetwork(),
      'lastConversationAt': _lastConversationAt?.toIso8601String(),
      'sttFailures': _sttFailures,
      'apiFailures': _apiFailures,
      'lastError': _lastError,
    }..removeWhere((key, value) => value == null);
  }

  Future<void> _sendHeartbeat() async {
    // 前回の送信が通信待ちで残っているときは重ねて送らない
    if (_sending) return;
    _sending = true;
    try {
      final payload = await _buildPayload();
      await http
          .post(
            Uri.parse('$kApiBaseUrl/api/heartbeat'),
            headers: {
              'Content-Type': 'application/json',
              'x-functions-key': kApiFunctionKey,
              if (kTenantId.isNotEmpty) 'x-tenant-id': kTenantId,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // 監視の失敗で会話を止めない。送れなかった分は次回の送信で追いつく。
    } finally {
      _sending = false;
    }
  }
}
