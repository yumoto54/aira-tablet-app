import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:aira_tablet_app/monitoring/network_status.dart';

void main() {
  test('通信そのものの失敗は警告の対象', () {
    expect(NetworkStatus.isNetworkError(const SocketException('Failed host lookup')), isTrue);
    expect(NetworkStatus.isNetworkError(http.ClientException('x')), isTrue);
  });

  test('サーバーのエラーや時間切れは警告の対象にしない', () {
    expect(NetworkStatus.isNetworkError(Exception('Chat API failed: 500')), isFalse);
    expect(NetworkStatus.isNetworkError(TimeoutException('slow')), isFalse);
  });

  test('失敗で警告が出て、成功で消える', () {
    final s = NetworkStatus.instance;
    s.reportSuccess();
    s.reportFailure(Exception('Speak API failed: 500'));
    expect(s.offline.value, isFalse);
    s.reportFailure(const SocketException('Failed host lookup'));
    expect(s.offline.value, isTrue);
    s.reportSuccess();
    expect(s.offline.value, isFalse);
  });
}
