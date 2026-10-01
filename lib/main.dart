import 'dart:async';
import 'dart:convert';
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

  AppState _state = AppState.idle;
  AppLocale _locale = AppLocale.en;
  String _recognizedText = '';
  String _airaReplyText = '';
  String _currentMouthShape = 'neutral';
  String _errorMessage = '';

  bool _speechAvailable = false;
  Timer? _mouthCueTimer;

  /// 読み上げまで終わった会話の回数
  int _completedTurns = 0;

  /// アンケートの口頭案内を流したかどうか。1セッションに1回だけにする。
  bool _surveyInviteSpoken = false;

  AppStrings get _strings => AppStrings.of(_locale);

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _mouthCueTimer?.cancel();
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

      await _playAudioWithMouthSync(audioBase64, mouthCues);
    } catch (e) {
      setState(() {
        _state = AppState.idle;
        _errorMessage = 'Error: $e\n\nMake sure the backend is running (npm start in freedom-ramen-avatar-backend)';
      });
    }
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

  Color _getMouthColor(String mouthShape) {
    switch (mouthShape) {
      case 'neutral':
        return Colors.grey;
      case 'A':
        return Colors.red;
      case 'E':
        return Colors.orange;
      case 'O':
        return Colors.yellow;
      case 'MBP':
        return Colors.green;
      case 'FV':
        return Colors.blue;
      case 'TH':
        return Colors.purple;
      case 'L':
        return Colors.pink;
      default:
        return Colors.grey;
    }
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
              child: Container(
                width: 400,
                height: 400,
                color: const Color(0xFFF5F5DC),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: 120,
                    height: 80,
                    color: _getMouthColor(_currentMouthShape),
                    child: Center(
                      child: Text(
                        _currentMouthShape,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
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
