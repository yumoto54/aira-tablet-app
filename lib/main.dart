import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'app_config.dart';
import 'l10n/app_locale.dart';
import 'l10n/app_strings.dart';
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

class _AiraHomePageState extends State<AiraHomePage> {
  /// 何回会話が成立したらアンケートに口頭で誘うか
  static const int _turnsBeforeSurveyInvite = 3;

  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Random _random = Random();

  AppState _state = AppState.idle;
  AppLocale _locale = AppLocale.en;
  String _recognizedText = '';
  String _airaReplyText = '';
  String _currentMouthShape = 'neutral';
  String _errorMessage = '';

  bool _speechAvailable = false;
  Timer? _mouthCueTimer;

  // まばたき: 一定間隔でランダムに目を閉じる。喋っているかどうかに関わらず動く。
  bool _eyesOpen = true;
  Timer? _blinkTimer;

  /// 読み上げまで終わった会話の回数
  int _completedTurns = 0;

  /// アンケートの口頭案内を流したかどうか。1セッションに1回だけにする。
  bool _surveyInviteSpoken = false;

  AppStrings get _strings => AppStrings.of(_locale);

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _scheduleNextBlink();
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
    return 'assets/avatar/combined/AIRA_combo_${eyeKey}_$mouthKey.png';
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

  @override
  void dispose() {
    _mouthCueTimer?.cancel();
    _blinkTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (error) {
          setState(() {
            _errorMessage = 'Speech error: ${error.errorMsg}';
          });
        },
      );
      setState(() {});
    } catch (e) {
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

  Future<void> _toggleRecording() async {
    if (_state == AppState.recording) {
      await _stopRecording();
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

    setState(() {
      _state = AppState.recording;
      _recognizedText = '';
      _airaReplyText = '';
      _errorMessage = '';
    });

    await _speech.listen(
      onResult: (result) {
        setState(() {
          _recognizedText = result.recognizedWords;
        });
      },
      listenOptions: stt.SpeechListenOptions(
        localeId: _locale.sttLocaleId,
      ),
    );
  }

  Future<void> _stopRecording() async {
    await _speech.stop();

    // "hello"のような短い発話だと、stop()が返った直後にはまだ
    // 認識エンジンの最終結果(onResult)が届いていないことがある。
    // 長い文章では誤差に隠れて気づかなかったが、短い発話では
    // 結果が空のまま次に進んでしまい、「認識されなかった」ことになっていた。
    // 400msでは"how are you"(3単語)は直ったが"hi"/"hello"(1単語)には
    // 足りなかったため、200ms刻みで最大1200msまで粘り強く待つ。
    // (届いた時点ですぐ抜けるので、通常ケースへの遅延影響はない)
    var waitedMs = 0;
    const maxWaitMs = 1200;
    const pollIntervalMs = 200;
    while (_recognizedText.isEmpty && waitedMs < maxWaitMs) {
      await Future.delayed(const Duration(milliseconds: pollIntervalMs));
      waitedMs += pollIntervalMs;
    }

    setState(() {
      _state = AppState.sending;
    });

    if (_recognizedText.isEmpty) {
      setState(() {
        _state = AppState.idle;
        _errorMessage = 'No speech recognized';
      });
      return;
    }

    await _sendToBackend();
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

  Future<void> _sendToBackend() async {
    try {
      final chatResponse = await http.post(
        Uri.parse('$kApiBaseUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'utterance': _recognizedText,
          'locale': _locale.tag,
        }),
      );

      if (chatResponse.statusCode != 200) {
        throw Exception('Chat API failed: ${chatResponse.statusCode}');
      }

      final chatData = jsonDecode(chatResponse.body);
      final replyText = chatData['text'] as String;
      final spokenText = _withSurveyInvitation(replyText);

      setState(() {
        _airaReplyText = spokenText;
      });

      final speakResponse = await http.post(
        Uri.parse('$kApiBaseUrl/api/speak'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'text': spokenText,
          'locale': _locale.tag,
        }),
      );

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
      setState(() {
        _state = AppState.idle;
        _errorMessage = 'Error: $e\n\nMake sure the backend is running (npm start in freedom-ramen-avatar-backend)';
      });
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
              // 読み上げ終了をもって1ターン成立とみなす
              _completedTurns++;
            });
          }
        },
      );

      await _audioPlayer.play();
    } catch (e) {
      setState(() {
        _state = AppState.idle;
        _errorMessage = 'Audio playback error: $e';
      });
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
            child: Center(
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
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'State: ${_state.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('Recognized: $_recognizedText'),
                const SizedBox(height: 8),
                Text('AIRA Reply: $_airaReplyText'),
                const SizedBox(height: 8),
                if (_errorMessage.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.red[100],
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(32),
            child: SizedBox(
              width: 120,
              height: 120,
              child: FloatingActionButton(
                onPressed: _state == AppState.idle || _state == AppState.recording
                    ? _toggleRecording
                    : null,
                backgroundColor:
                    _state == AppState.recording ? Colors.red : Colors.blue,
                child: Icon(
                  _state == AppState.recording ? Icons.stop : Icons.mic,
                  size: 48,
                ),
              ),
            ),
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