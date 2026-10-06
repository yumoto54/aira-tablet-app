import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'app_config.dart';
import 'l10n/app_locale.dart';
import 'l10n/app_strings.dart';
import 'monitoring/device_monitor.dart';
import 'survey/survey_flow_page.dart';

void main() {
  runApp(const AiraApp());
}

class AiraApp extends StatelessWidget {
  const AiraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AIRA Tablet App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AiraHomePage(),
    );
  }
}

enum AppState {
  idle,
  recording,
  sending,
  speaking,
}

class MouthCue {
  final String mouthShape;
  final String fileName;
  final int audioOffsetMs;

  MouthCue({
    required this.mouthShape,
    required this.fileName,
    required this.audioOffsetMs,
  });

  factory MouthCue.fromJson(Map<String, dynamic> json) {
    return MouthCue(
      mouthShape: json['mouthShape'] as String,
      fileName: json['fileName'] as String,
      audioOffsetMs: (json['audioOffsetMs'] as num).round(),
    );
  }
}

class AiraHomePage extends StatefulWidget {
  const AiraHomePage({super.key});

  @override
  State<AiraHomePage> createState() => _AiraHomePageState();
}

class _AiraHomePageState extends State<AiraHomePage>
    with SingleTickerProviderStateMixin {
  /// 何回会話が成立したらアンケートに口頭で誘うか
  static const int _turnsBeforeSurveyInvite = 3;

  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Random _random = Random();

  AppState _state = AppState.idle;
  AppLocale _locale = AppLocale.en;

  /// アバターの絵柄('photo' / 'anime')。起動時はビルド指定(kAvatarStyle)、
  /// 画面上のボタンでその場で切り替えられる(会場デモ用)。
  String _avatarStyle = kAvatarStyle;
  String _recognizedText = '';
  String _airaReplyText = '';
  String _currentMouthShape = 'neutral';
  String _errorMessage = '';

  bool _speechAvailable = false;
  Timer? _mouthCueTimer;

  /// マイクボタンの「聞いています」リングを脈打たせるためのアニメーション。
  /// 録音中かどうかに関わらず回し続け、表示側(AnimatedBuilder)で
  /// 録音中だけリングを見せる。開始/停止の分岐を持たない分、単純にしている。
  late final AnimationController _pulseController;

  // まばたき: 一定間隔でランダムに目を閉じる。喋っているかどうかに関わらず動く。
  bool _eyesOpen = true;
  Timer? _blinkTimer;

  /// 読み上げまで終わった会話の回数
  int _completedTurns = 0;

  /// 画面に出しているQRコードのURL。出していないときは null。
  /// バックエンドが返答に qr を付けたときだけ出す(出す・出さないはサーバー側の設定)。
  String? _qrUrl;
  Timer? _qrTimer;

  /// QRコードを出しっぱなしにする時間。来場者がスマホで読み取るのに十分な長さ。
  static const Duration _qrDisplayDuration = Duration(seconds: 60);

  /// 直近の会話。「はい」「それお願いします」のような短い返事を、AIが
  /// 直前のやりとりと結びつけて理解できるように、バックエンドへ一緒に送る。
  final List<Map<String, String>> _chatHistory = [];
  DateTime? _lastChatAt;

  /// この時間しゃべりかけられなかったら、次の来場者とみなして履歴を捨てる。
  /// 前の人との会話の続きとして答えてしまわないため。
  static const Duration _chatHistoryTimeout = Duration(seconds: 90);
  static const int _maxChatHistoryMessages = 6;

  /// アンケートの口頭案内を流したかどうか。1セッションに1回だけにする。
  bool _surveyInviteSpoken = false;

  // --- アトラクトモード: 誰も話しかけていない時間が一定続いたら、
  // AIRA側から自分で声をかけてブース前を通る人を呼び込む ---

  /// アイドル(誰も操作していない)状態がこの時間続いたら呼び込みを話す。
  static const Duration _attractIdleDelay = Duration(seconds: 35);

  Timer? _attractTimer;

  /// 今再生している発話が、ユーザーとの会話(通常ターン)ではなく
  /// アトラクトモードの呼び込みかどうか。会話ターン数のカウントや
  /// アンケート導線の挿入はユーザーとの実際の会話にだけ適用したいので、
  /// それらと区別するために使う。
  bool _isAttractSpeech = false;

  /// 聞き取りの終了処理が二重に走らないようにする。
  /// stop のタップと、認識エンジン側のタイムアウト/エラーがほぼ同時に来るため。
  bool _finishingListen = false;

  /// 今の聞き取りセッションで、エンジンが実際に listening になったか。
  /// 前回セッションの遅延した done 通知で、聞き始め直後に閉じてしまわないようにする。
  bool _heardListeningStatus = false;

  AppStrings get _strings => AppStrings.of(_locale);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    DeviceMonitor.instance.stateProvider = () => _state.name;
    DeviceMonitor.instance.start();
    _initSpeech();
    _scheduleNextBlink();
    _scheduleAttractTimer();
    // 会話中に口の形が切り替わるたびに初回デコードが走ると、そこだけ
    // カクつく(特に非力な端末では顕著)。起動時に全アバター画像を
    // 一度デコードしてキャッシュしておくことで、本番中のジャンクを避ける。
    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheAvatarImages());
  }

  /// 目の開閉×口の形(8種)をあらかじめ合成した16枚の画像パスを列挙する。
  ///
  /// 以前はベース/目/口の3枚をStackで毎フレーム重ねていたが、タブレット上で
  /// 各レイヤーの境界がわずかにズレて白い縁取りのように見える現象が出たため、
  /// ビルド時(事前)に全組み合わせを1枚絵として合成しておく方式に変更した。
  /// こうすると実機側では単純な1枚のImage差し替えだけで済み、
  /// レイヤー合成のズレが原理的に起こらない。
  static const List<String> _mouthShapeKeys = [
    'neutral', 'A', 'E', 'O', 'MPB', 'FV', 'TH', 'L',
  ];

  /// バックエンドが返す mouthShape コード(neutral/A/E/O/MBP/FV/TH/L)を、
  /// 合成済みアセットのファイル名に使っているキーに正規化する。
  ///
  /// 注意: バックエンドのコードは "MBP" だが、アートワークのファイル名は
  /// "MPB"(文字の並び順違い)になっているため、ここで吸収している。
  String _normalizedMouthKey(String mouthShape) {
    return mouthShape == 'MBP' ? 'MPB' : mouthShape;
  }

  String _comboAssetPath(bool eyesOpen, String mouthShape) {
    final eyeKey = eyesOpen ? 'open' : 'closed';
    final mouthKey = _normalizedMouthKey(mouthShape);
    final dir = _avatarStyle == 'anime' ? 'assets/avatar_anime' : 'assets/avatar';
    return '$dir/combined/AIRA_combo_${eyeKey}_$mouthKey.png';
  }

  Future<void> _precacheAvatarImages() async {
    final paths = <String>[
      for (final eyesOpen in [true, false])
        for (final mouthShape in _mouthShapeKeys)
          _comboAssetPath(eyesOpen, mouthShape),
    ];

    for (final path in paths) {
      if (!mounted) return;
      await precacheImage(AssetImage(path), context);
    }
  }

  /// 絵柄を実写風⇔アニメ風に切り替える。切り替え先の画像を先に読み込んでから
  /// 入れ替えるので、切り替えの瞬間にちらつかない。
  Future<void> _toggleAvatarStyle() async {
    final next = _avatarStyle == 'anime' ? 'photo' : 'anime';
    final previous = _avatarStyle;
    _avatarStyle = next; // _comboAssetPath が次の絵柄を指すようにして先読みする
    await _precacheAvatarImages();
    _avatarStyle = previous;
    if (!mounted) return;
    setState(() => _avatarStyle = next);
  }

  @override
  void dispose() {
    _mouthCueTimer?.cancel();
    _blinkTimer?.cancel();
    _attractTimer?.cancel();
    _qrTimer?.cancel();
    _pulseController.dispose();
    _audioPlayer.dispose();
    DeviceMonitor.instance.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (error) {
          // error_no_match / error_speech_timeout は「何も聞き取れなかった」とき。
          // ここで終わらせないと、赤いマイクのまま十数秒固まったように見える。
          if (_state == AppState.recording) {
            unawaited(_finishListen(userStopped: false));
            return;
          }
          DeviceMonitor.instance.recordSttFailure(error.errorMsg);
          setState(() {
            _errorMessage = 'Speech error: ${error.errorMsg}';
          });
        },
        onStatus: (status) {
          if (status == stt.SpeechToText.listeningStatus) {
            _heardListeningStatus = true;
            return;
          }
          if (_state != AppState.recording || _finishingListen) return;
          if (!_heardListeningStatus) return;
          if (status == stt.SpeechToText.notListeningStatus ||
              status == stt.SpeechToText.doneStatus) {
            unawaited(_finishListen(userStopped: false));
          }
        },
      );
      setState(() {});
    } catch (e) {
      DeviceMonitor.instance.recordSttFailure('init failed: $e');
      setState(() {
        _errorMessage = 'Failed to initialize speech: $e';
      });
    }
  }

  /// 2.5〜5.5秒ごとにランダムな間隔でまばたきさせる。
  /// 毎回同じ間隔だと機械的に見えるので、少し幅を持たせている。
  void _scheduleNextBlink() {
    final delayMs = 2500 + _random.nextInt(3000);
    _blinkTimer = Timer(Duration(milliseconds: delayMs), () async {
      if (!mounted) return;
      setState(() => _eyesOpen = false);
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      setState(() => _eyesOpen = true);
      _scheduleNextBlink();
    });
  }

  /// アイドル状態が _attractIdleDelay 続いたら _playAttractMessage() を呼ぶ
  /// タイマーを(再)設定する。ユーザーが話しかけ始めたり、画面遷移したりする
  /// たびに呼び直して、タイマーをリセットする。
  void _scheduleAttractTimer() {
    _attractTimer?.cancel();
    _attractTimer = Timer(_attractIdleDelay, _playAttractMessage);
  }

  /// 誰も話しかけていない状態が続いたときに、AIRAから自分で声をかけて
  /// ブース前を通る人を呼び込む。通常の会話ターンとは独立した仕組みなので、
  /// 失敗しても画面にエラーを出さず、静かに諦めて次のタイマーだけ再設定する
  /// (バックエンドが一時的に落ちていても、通常の会話機能には影響させない)。
  Future<void> _playAttractMessage() async {
    if (!mounted || _state != AppState.idle) return;

    final message =
        _strings.attractMessages[_random.nextInt(_strings.attractMessages.length)];

    _isAttractSpeech = true;
    final spoke = await _speakText(
      message,
      // API応答を待っている間にユーザーが話しかけ始めていたら、
      // 今さら呼び込みを再生してユーザーの発話に被せない。
      shouldContinue: () => mounted && _state == AppState.idle,
    );
    if (!spoke) {
      // 発話自体に失敗した場合(バックエンド未起動など)は、会話機能には
      // 影響させず、次の呼び込みタイミングだけ再設定しておく。
      _isAttractSpeech = false;
      if (mounted && _state == AppState.idle) {
        _scheduleAttractTimer();
      }
    }
  }

  /// 指定したテキストをバックエンドのTTSで読み上げ、口の動きを同期させる。
  /// アトラクトモードの呼び込みや、聞き取れなかったときの聞き返しなど、
  /// 「ユーザーの発話への通常の返答」以外の場面でAIRAに話させたいときに使う。
  ///
  /// 成功して再生まで進んだ場合は true、API呼び出し等で失敗した場合は false を返す。
  /// 失敗時の状態の後始末(タイマーの再設定など)は呼び出し側の責務とする。
  Future<bool> _speakText(
    String text, {
    bool Function()? shouldContinue,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final speakResponse = await http
          .post(
            Uri.parse('$kApiBaseUrl/api/speak'),
            headers: {
              'Content-Type': 'application/json',
              'x-functions-key': kApiFunctionKey,
            },
            body: jsonEncode({
              'text': text,
              'locale': _locale.tag,
            }),
          )
          .timeout(timeout);

      if (speakResponse.statusCode != 200) {
        throw Exception('Speak API failed: ${speakResponse.statusCode}');
      }

      if (!mounted) return false;
      if (shouldContinue != null && !shouldContinue()) return false;

      final speakData = jsonDecode(speakResponse.body);
      final audioBase64 = speakData['audioBase64'] as String;
      final mouthCuesJson = speakData['mouthCues'] as List;
      final mouthCues = mouthCuesJson
          .map((json) => MouthCue.fromJson(json as Map<String, dynamic>))
          .toList();

      setState(() {
        _airaReplyText = text;
      });

      await _playAudioWithMouthSync(audioBase64, _smoothMouthCues(mouthCues));
      return true;
    } catch (e) {
      DeviceMonitor.instance.recordApiFailure('speak: $e');
      return false;
    }
  }

  Future<void> _toggleRecording() async {
    if (_state == AppState.recording) {
      await _finishListen(userStopped: true);
    } else if (_state == AppState.idle) {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!_speechAvailable) {
      setState(() {
        _errorMessage = 'Speech recognition not available. Please check microphone permissions.';
      });
      return;
    }

    // ユーザーが自分から話しかけ始めたので、呼び込み発話が割り込まないように
    // アトラクトモードのタイマーを止めておく。会話が終わってアイドルに
    // 戻ったタイミングで改めて仕掛け直す。
    _attractTimer?.cancel();

    setState(() {
      _state = AppState.recording;
      _recognizedText = '';
      _airaReplyText = '';
      _errorMessage = '';
      _heardListeningStatus = false;
    });

    await _speech.listen(
      onResult: (result) {
        setState(() {
          _recognizedText = result.recognizedWords;
        });
      },
      listenOptions: stt.SpeechListenOptions(
        localeId: _locale.sttLocaleId,
        // 無音が続いたらこちらから切る。指定しないと Android 側の
        // タイムアウト(十秒前後)まで赤いマイクのまま待たされる。
        // ただし2秒だと「押してから話し始めるまでの間」にも引っかかり、
        // 何もしゃべっていないのに即座に「聞き取れませんでした」になって
        // しまっていたため、話し始めの間も見込んで余裕を持たせる。
        pauseFor: const Duration(seconds: 5),
        listenFor: const Duration(seconds: 12),
        cancelOnError: true,
      ),
    );
  }

  /// 聞き取りを終えて、結果があれば会話へ、なければすぐマイクを戻す。
  Future<void> _finishListen({required bool userStopped}) async {
    if (_finishingListen || _state != AppState.recording) return;
    _finishingListen = true;

    try {
      if (_speech.isListening) {
        try {
          // ユーザーが止めた直後は "hi" のような短い語の最終結果が遅れがちなので
          // stop で確定を待つ。エンジン側がタイムアウトした空振りは cancel で切る。
          if (userStopped || _recognizedText.isNotEmpty) {
            await _speech.stop().timeout(const Duration(seconds: 2));
          } else {
            await _speech.cancel().timeout(const Duration(seconds: 1));
          }
        } on TimeoutException {
          unawaited(_speech.cancel());
        }
      }

      // ユーザーが止めた直後は、短い発話の最終結果が遅れて届くことがある。
      // エンジン側のタイムアウトで終わった場合は、待っても空のままなので粘らない。
      if (userStopped && _recognizedText.isEmpty) {
        var waitedMs = 0;
        const maxWaitMs = 600;
        const pollIntervalMs = 150;
        while (_recognizedText.isEmpty && waitedMs < maxWaitMs) {
          await Future.delayed(const Duration(milliseconds: pollIntervalMs));
          waitedMs += pollIntervalMs;
        }
      }

      if (!mounted) return;

      if (_recognizedText.isEmpty) {
        await _handleUnrecognizedSpeech();
        return;
      }

      setState(() {
        _state = AppState.sending;
      });
      await _sendToBackend();
    } finally {
      _finishingListen = false;
    }
  }

  /// 聞き取れなかったときは、先にマイクを使える状態に戻してから聞き返す。
  /// 聞き返しのTTSを待っている間に画面が固まったように見えないようにするため。
  Future<void> _handleUnrecognizedSpeech() async {
    DeviceMonitor.instance.recordSttFailure('no speech recognized');
    setState(() {
      _state = AppState.idle;
      _errorMessage = 'No speech recognized';
    });

    final spoke = await _speakText(
      _strings.voiceRetryPrompt,
      timeout: const Duration(seconds: 3),
      shouldContinue: () => mounted && _state == AppState.idle,
    );
    if (!spoke && mounted && _state == AppState.idle) {
      _scheduleAttractTimer();
    }
  }

  /// 3回会話が成立したあと、次の返答の末尾にアンケートの案内を足す。
  ///
  /// 毎回言うと接客がしつこくなるので、アプリを立ち上げてから1回だけにしている。
  String _withSurveyInvitation(String replyText) {
    if (_surveyInviteSpoken) return replyText;
    if (_completedTurns < _turnsBeforeSurveyInvite) return replyText;

    _surveyInviteSpoken = true;
    return '$replyText ${_strings.surveyInvitation}';
  }

  void _showQr(String url) {
    _qrTimer?.cancel();
    _qrTimer = Timer(_qrDisplayDuration, _hideQr);
    if (!mounted) return;
    setState(() => _qrUrl = url);
  }

  void _hideQr() {
    _qrTimer?.cancel();
    _qrTimer = null;
    if (!mounted || _qrUrl == null) return;
    setState(() => _qrUrl = null);
  }

  Widget _buildQrCard(String url) {
    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // スキャンしやすいよう、白地に黒の標準的な見た目にする
            QrImageView(
              data: url,
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 200,
              child: Text(
                _strings.qrCaption,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: _hideQr,
              child: Text(_strings.close),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendToBackend() async {
    try {
      final utterance = _recognizedText;
      final startedAt = DateTime.now();
      if (_lastChatAt == null ||
          startedAt.difference(_lastChatAt!) > _chatHistoryTimeout) {
        _chatHistory.clear();
      }

      final chatResponse = await http
          .post(
            Uri.parse('$kApiBaseUrl/api/chat'),
            headers: {
              'Content-Type': 'application/json',
              'x-functions-key': kApiFunctionKey,
            },
            body: jsonEncode({
              'utterance': utterance,
              'locale': _locale.tag,
              'history': _chatHistory,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (chatResponse.statusCode != 200) {
        throw Exception('Chat API failed: ${chatResponse.statusCode}');
      }

      final chatData = jsonDecode(chatResponse.body);
      final replyText = chatData['text'] as String;

      // サーバーが qr を付けてきたときだけ、その URL の QR コードを画面に出す。
      // 付いていない返答では、前の QR を引きずらないよう消す。
      final qrData = chatData['qr'];
      final qrUrl =
          (qrData is Map && qrData['url'] is String) ? qrData['url'] as String : null;
      if (qrUrl != null) {
        _showQr(qrUrl);
      } else {
        _hideQr();
      }

      _chatHistory
        ..add({'role': 'user', 'content': utterance})
        ..add({'role': 'assistant', 'content': replyText});
      while (_chatHistory.length > _maxChatHistoryMessages) {
        _chatHistory.removeAt(0);
      }
      _lastChatAt = DateTime.now();
      final spokenText = _withSurveyInvitation(replyText);

      setState(() {
        _airaReplyText = spokenText;
      });

      final speakResponse = await http
          .post(
            Uri.parse('$kApiBaseUrl/api/speak'),
            headers: {
              'Content-Type': 'application/json',
              'x-functions-key': kApiFunctionKey,
            },
            body: jsonEncode({
              'text': spokenText,
              'locale': _locale.tag,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (speakResponse.statusCode != 200) {
        throw Exception('Speak API failed: ${speakResponse.statusCode}');
      }

      final speakData = jsonDecode(speakResponse.body);
      final audioBase64 = speakData['audioBase64'] as String;
      final mouthCuesJson = speakData['mouthCues'] as List;
      final mouthCues = mouthCuesJson
          .map((json) => MouthCue.fromJson(json as Map<String, dynamic>))
          .toList();

      await _playAudioWithMouthSync(audioBase64, _smoothMouthCues(mouthCues));
    } catch (e) {
      DeviceMonitor.instance.recordApiFailure('chat: $e');
      setState(() {
        _state = AppState.idle;
        _errorMessage = 'Error: $e\n\nMake sure the backend is running (npm start in freedom-ramen-avatar-backend)';
      });
      _scheduleAttractTimer();
    }
  }

  /// 短すぎる口の形の変化は不自然(パクパクしすぎ)に見えるので間引く。
  ///
  /// 直前に採用した cue から minDurationMs 未満のタイミングで来る cue は
  /// 無視し、ある程度の時間は同じ口の形を保たせる。数値を大きくするほど
  /// 動きは穏やかに、小さくするほど口の動きは忠実(だが激しく)なる。
  List<MouthCue> _smoothMouthCues(
    List<MouthCue> cues, {
    int minDurationMs = 110,
  }) {
    if (cues.isEmpty) return cues;

    final result = <MouthCue>[cues.first];
    for (final cue in cues.skip(1)) {
      if (cue.audioOffsetMs - result.last.audioOffsetMs < minDurationMs) {
        continue;
      }
      result.add(cue);
    }
    return result;
  }

  Future<void> _playAudioWithMouthSync(
    String audioBase64,
    List<MouthCue> mouthCues,
  ) async {
    setState(() {
      _state = AppState.speaking;
      _currentMouthShape = 'neutral';
    });

    try {
      final audioBytes = base64Decode(audioBase64);
      await _audioPlayer.setAudioSource(
        _Base64AudioSource(audioBytes),
      );

      int cueIndex = 0;

      _mouthCueTimer?.cancel();
      _mouthCueTimer = Timer.periodic(
        const Duration(milliseconds: 50),
        (timer) async {
          final position = await _audioPlayer.position;
          final positionMs = position.inMilliseconds;

          while (cueIndex < mouthCues.length &&
              mouthCues[cueIndex].audioOffsetMs <= positionMs) {
            setState(() {
              _currentMouthShape = mouthCues[cueIndex].mouthShape;
            });
            cueIndex++;
          }

          if (_audioPlayer.playerState.processingState ==
              ProcessingState.completed) {
            timer.cancel();
            setState(() {
              _state = AppState.idle;
              _currentMouthShape = 'neutral';
              // アトラクトモードの自主発話はユーザーとの会話ターンではないので、
              // アンケート誘導のカウントには含めない。
              if (!_isAttractSpeech) {
                _completedTurns++;
                DeviceMonitor.instance.recordConversation();
              }
            });
            _isAttractSpeech = false;
            _scheduleAttractTimer();
          }
        },
      );

      await _audioPlayer.play();
    } catch (e) {
      DeviceMonitor.instance.recordApiFailure('audio: $e');
      setState(() {
        _state = AppState.idle;
        _errorMessage = 'Audio playback error: $e';
      });
      _isAttractSpeech = false;
      _scheduleAttractTimer();
    }
  }

  Future<void> _openSurvey() async {
    // 画面を離れる前に、読み上げ中の音声と聞き取りを止める。
    // 戻ってきたときに前の発話の続きが鳴り出さないようにするため。
    _mouthCueTimer?.cancel();
    await _audioPlayer.stop();
    if (_speech.isListening) {
      await _speech.cancel();
    }
    // アンケート画面にいる間にAIRAが勝手に喋り出さないように止めておく。
    _attractTimer?.cancel();
    _isAttractSpeech = false;

    if (!mounted) return;

    setState(() {
      _state = AppState.idle;
      _currentMouthShape = 'neutral';
    });

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SurveyFlowPage(locale: _locale),
      ),
    );

    // アンケート画面から戻ってきたら、再びアイドル検知を始める。
    if (mounted) {
      _scheduleAttractTimer();
    }
  }

  /// 状態ごとのアイコン・ラベル・色。見た瞬間に「いまどの段階か」が
  /// わかるように、マイクボタンと状態バッジの両方でこの3点セットを使う。
  (IconData, String, Color) _statusVisual(AppState state) {
    return switch (state) {
      AppState.idle => (Icons.mic_none, _strings.mainStatusIdle, Colors.blueGrey),
      AppState.recording => (Icons.graphic_eq, _strings.mainStatusListening, Colors.red),
      AppState.sending => (Icons.hourglass_top, _strings.mainStatusSending, Colors.orange),
      AppState.speaking => (Icons.volume_up, _strings.mainStatusSpeaking, Colors.green),
    };
  }

  Widget _buildStatusBadge() {
    final (icon, label, color) = _statusVisual(_state);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 18),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptBubble({
    required IconData icon,
    required String text,
    required bool alignRight,
  }) {
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: alignRight ? Colors.blue[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.black54),
          const SizedBox(width: 8),
          Flexible(child: Text(text)),
        ],
      ),
    );
    return Row(
      mainAxisAlignment:
          alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [bubble],
    );
  }

  /// マイクボタン本体。「押す→聞いている(赤く脈打つ)→送信中(スピナー)→
  /// AIRAが話す(緑)」が一目でわかるよう、状態ごとに見た目をはっきり変える。
  Widget _buildMicButton() {
    final (_, label, color) = _statusVisual(_state);
    final tappable = _state == AppState.idle || _state == AppState.recording;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 録音中だけ、ボタンの外周に脈打つリングを表示して
              // 「いま聞き取っている」ことを強調する。
              if (_state == AppState.recording)
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final scale = 1.0 + (_pulseController.value * 0.35);
                    final opacity = 1.0 - _pulseController.value;
                    return Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: opacity.clamp(0.0, 1.0),
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              SizedBox(
                width: 120,
                height: 120,
                child: FloatingActionButton(
                  onPressed: tappable ? _toggleRecording : null,
                  backgroundColor: color,
                  child: _state == AppState.sending
                      ? const SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : Icon(
                          _state == AppState.recording
                              ? Icons.stop
                              : _state == AppState.speaking
                                  ? Icons.volume_up
                                  : Icons.mic,
                          size: 48,
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _state == AppState.recording ? _strings.voiceStop : label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AIRA Tablet App'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // マイクは画面下、アンケート導線は画面上。押し間違えないように離しておく。
        actions: [
          SegmentedButton<AppLocale>(
            segments: [
              for (final locale in AppLocale.values)
                ButtonSegment<AppLocale>(
                  value: locale,
                  label: Text(locale.switcherLabel),
                ),
            ],
            selected: {_locale},
            onSelectionChanged: (selection) {
              setState(() => _locale = selection.first);
            },
            showSelectedIcon: false,
          ),
          const SizedBox(width: 12),
          IconButton.filledTonal(
            tooltip: _avatarStyle == 'anime' ? 'Photo style' : 'Anime style',
            icon: const Icon(Icons.face_retouching_natural),
            onPressed: _toggleAvatarStyle,
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: _openSurvey,
            icon: const Icon(Icons.card_giftcard),
            label: Text(_strings.surveyCta),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    // 以前はAnimatedSwitcherで毎回フェードさせていたが、喋っている間は
                    // 口の形が(多いと100ms間隔程度で)頻繁に変わるため、そのたびに顔
                    // 全体がフェードアウト/インし、「ずっと点滅している」ように見えて
                    // しまっていた。実際の口の動きは瞬間的な切り替わりの方が自然に
                    // 見えるため、フェードなしで即座に切り替える。
                    // gaplessPlayback を付けることで、アセット切り替え中に一瞬
                    // 画像が消える(空白になる)のも防いでいる。
                    child: Image.asset(
                      _comboAssetPath(_eyesOpen, _currentMouthShape),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                if (_qrUrl != null)
                  Positioned(
                    right: 24,
                    top: 24,
                    child: _buildQrCard(_qrUrl!),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: _buildStatusBadge()),
                if (_recognizedText.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildTranscriptBubble(
                    icon: Icons.person,
                    text: _recognizedText,
                    alignRight: true,
                  ),
                ],
                if (_airaReplyText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildTranscriptBubble(
                    icon: Icons.smart_toy,
                    text: _airaReplyText,
                    alignRight: false,
                  ),
                ],
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.red[100],
                      child: Text(
                        _errorMessage,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(32),
            child: _buildMicButton(),
          ),
        ],
      ),
    );
  }
}

class _Base64AudioSource extends StreamAudioSource {
  final Uint8List _buffer;

  _Base64AudioSource(this._buffer);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _buffer.length;
    return StreamAudioResponse(
      sourceLength: _buffer.length,
      contentLength: end - start,
      offset: start,
      contentType: 'audio/mpeg',
      stream: Stream.value(_buffer.sublist(start, end)),
    );
  }
}