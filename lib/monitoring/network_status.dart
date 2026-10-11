import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 「インターネットに出られない」状態を画面に知らせるための共有状態。
///
/// Wi-Fi につながっていても回線が死んでいると、API呼び出しが
/// 「サーバー名を引けない(Failed host lookup)」で失敗する。会場でそれが
/// 起きたとき、来場者にもスタッフにも分かるよう警告を出し、
/// 呼び込み発話の無駄な再試行(通信失敗の累積)を止めるために使う。
class NetworkStatus {
  NetworkStatus._();

  static final NetworkStatus instance = NetworkStatus._();

  /// true の間、画面に「インターネットがありません」の警告を出す。
  final ValueNotifier<bool> offline = ValueNotifier<bool>(false);

  /// 通信そのものの失敗(サーバーまで届かない)かどうか。
  /// サーバーが返した 4xx/5xx(Exception('... failed: 500') など)は含めない。
  /// 時間切れ(TimeoutException)も含めない: AIの返答が遅いだけで
  /// 「インターネットがありません」と誤って出さないため。
  static bool isNetworkError(Object error) {
    if (error is SocketException) return true;
    if (error is HandshakeException) return true;
    if (error is http.ClientException) return true;
    return false;
  }

  /// API呼び出しが失敗したときに呼ぶ。通信の失敗のときだけ警告を出す。
  void reportFailure(Object error) {
    if (isNetworkError(error)) offline.value = true;
  }

  /// サーバーから応答が返ったときに呼ぶ(警告を消す)。
  void reportSuccess() {
    offline.value = false;
  }

  /// 警告中に、軽い通信で回復を確かめる。応答が返れば(405 などでも)
  /// インターネットには出られている。
  Future<void> probe(String baseUrl) async {
    try {
      await http
          .head(Uri.parse(baseUrl))
          .timeout(const Duration(seconds: 4));
      reportSuccess();
    } catch (_) {
      // まだ出られない。警告は出したままにする。
    }
  }
}
