import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../l10n/app_locale.dart';
import '../../l10n/app_strings.dart';

/// アンケートの設問で音声入力を受け付けるボタン。
///
/// speech_to_text の SpeechToText() はパッケージ内でシングルトンになっているため、
/// メイン画面と同じ認識エンジンを共有する。initialize は初回だけ効く作りなので、
/// ここで呼び直しても二重初期化にはならない。
class VoiceCaptureButton extends StatefulWidget {
  const VoiceCaptureButton({
    super.key,
    required this.locale,
    required this.strings,
    required this.onFinalResult,
    this.iconOnly = false,
  });

  final AppLocale locale;
  final AppStrings strings;

  /// 聞き取りが確定したときに1度だけ呼ばれる
  final ValueChanged<String> onFinalResult;

  /// テキスト欄の横に置く小さいマイクとして描くかどうか
  final bool iconOnly;

  @override
  State<VoiceCaptureButton> createState() => _VoiceCaptureButtonState();
}

class _VoiceCaptureButtonState extends State<VoiceCaptureButton> {
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _listening = false;
  bool _unavailable = false;
  String _partialText = '';

  @override
  void dispose() {
    if (_listening) {
      _speech.cancel();
    }
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    final available = await _speech.initialize();
    if (!mounted) return;

    if (!available) {
      setState(() => _unavailable = true);
      return;
    }

    setState(() {
      _listening = true;
      _unavailable = false;
      _partialText = '';
    });

    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() => _partialText = result.recognizedWords);

        if (result.finalResult) {
          setState(() => _listening = false);
          widget.onFinalResult(result.recognizedWords);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        localeId: widget.locale.sttLocaleId,
        // 来場者が話し終えたら自動で止める。ブースでは「停止」を押し忘れるため。
        pauseFor: const Duration(seconds: 2),
        listenFor: const Duration(seconds: 15),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.iconOnly) {
      return IconButton.filledTonal(
        onPressed: _toggle,
        tooltip: _listening
            ? widget.strings.voiceStop
            : widget.strings.voiceFillName,
        icon: Icon(_listening ? Icons.stop : Icons.mic),
        iconSize: 28,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _toggle,
          icon: Icon(_listening ? Icons.stop : Icons.mic),
          label: Text(
            _listening
                ? widget.strings.voiceListening
                : widget.strings.voiceAnswerButton,
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            textStyle: const TextStyle(fontSize: 18),
            foregroundColor: _listening ? Colors.red : null,
          ),
        ),
        if (_partialText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '「$_partialText」',
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ),
        if (_unavailable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              widget.strings.voiceUnavailable,
              style: const TextStyle(color: Colors.red),
            ),
          ),
      ],
    );
  }
}
