import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../l10n/app_locale.dart';
import '../l10n/app_strings.dart';
import 'survey_api.dart';
import 'survey_complete_page.dart';
import 'survey_draft.dart';
import 'survey_options.dart';
import 'voice_match.dart';
import 'widgets/survey_choice_button.dart';
import 'widgets/voice_capture_button.dart';

/// 展示会限定のアンケート景品キャンペーン用の入力画面。
///
/// 1問ずつ進むウィザード。途中で送信に失敗しても回答は保持したままにして、
/// 該当の欄だけ直して送り直せるようにしている。
class SurveyFlowPage extends StatefulWidget {
  const SurveyFlowPage({
    super.key,
    required this.locale,
    this.httpClient,
  });

  final AppLocale locale;

  /// テストから差し替えるためのHTTPクライアント。実機では null のまま。
  final http.Client? httpClient;

  @override
  State<SurveyFlowPage> createState() => _SurveyFlowPageState();
}

const int _totalSteps = 5;

class _SurveyFlowPageState extends State<SurveyFlowPage> {
  final SurveyDraft _draft = SurveyDraft();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  int _step = 0;
  bool _submitting = false;

  /// 赤い帯に出す文言。APIが返した検証エラーをそのまま並べる場合もある。
  List<String> _errors = const [];

  /// 音声は拾えたが選択肢を特定できなかったときの案内
  String? _voiceHint;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  AppStrings get _strings => AppStrings.of(widget.locale);

  bool get _canAdvance {
    switch (_step) {
      case 0:
        return _draft.flavor != null;
      case 1:
        return _draft.satisfaction != null;
      case 2:
        return _draft.howHeard != null;
      case 3:
        return _nameController.text.trim().isNotEmpty;
      default:
        return true;
    }
  }

  void _goBack() {
    setState(() {
      _step--;
      _voiceHint = null;
    });
  }

  void _goNext() {
    if (_step == _totalSteps - 1) {
      _submit();
      return;
    }
    setState(() {
      _step++;
      _voiceHint = null;
    });
  }

  /// 音声の聞き取り結果を選択肢に対応づける。特定できなければ案内だけ出す。
  void _applyVoiceChoice<T>(
    String spoken,
    Map<T, List<String>> keywords,
    ValueChanged<T> onMatched,
  ) {
    final matched = matchSpokenChoice(spoken, keywords);
    setState(() {
      if (matched == null) {
        _voiceHint = _strings.voiceNoMatch;
      } else {
        _voiceHint = null;
        onMatched(matched);
      }
    });
  }

  void _applyVoiceRating(String spoken) {
    final matched = matchSpokenRating(spoken);
    setState(() {
      if (matched == null) {
        _voiceHint = _strings.voiceNoMatch;
      } else {
        _voiceHint = null;
        _draft.satisfaction = matched;
      }
    });
  }

  Future<void> _submit() async {
    _draft.name = _nameController.text;
    _draft.email = _emailController.text;

    final localErrors = _draft.validate(_strings);
    if (localErrors.isNotEmpty) {
      setState(() => _errors = localErrors);
      return;
    }

    setState(() {
      _submitting = true;
      _errors = const [];
    });

    final result = await submitSurvey(
      draft: _draft,
      locale: widget.locale,
      client: widget.httpClient,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    switch (result) {
      case SurveySubmitSuccess(:final code):
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => SurveyCompletePage(
              code: code,
              locale: widget.locale,
            ),
          ),
        );
      case SurveySubmitInvalid(:final details):
        // サーバーの文言をそのまま出す。どの欄が問題かを来場者とスタッフが見て判断できる。
        setState(() => _errors = details);
      case SurveySubmitFailed(:final debugMessage):
        debugPrint('[survey] submit failed: $debugMessage');
        setState(() => _errors = [_strings.submitNetworkError]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _strings;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.surveyTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            tooltip: strings.close,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildProgress(strings),
            if (_errors.isNotEmpty) _buildErrorBanner(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: _buildStepBody(strings),
                ),
              ),
            ),
            _buildBottomBar(strings),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(AppStrings strings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.stepIndicator(_step + 1, _totalSteps),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_step + 1) / _totalSteps,
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(32, 16, 32, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        border: Border.all(color: Colors.red),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final error in _errors)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      error,
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepBody(AppStrings strings) {
    switch (_step) {
      case 0:
        return _buildChoiceStep(
          strings: strings,
          question: strings.questionFlavor,
          onVoiceResult: (spoken) => _applyVoiceChoice<FlavorChoice>(
            spoken,
            kFlavorVoiceKeywords,
            (choice) => _draft.flavor = choice,
          ),
          choices: [
            for (final choice in FlavorChoice.values)
              SurveyChoiceButton(
                label: choice.label(strings),
                selected: _draft.flavor == choice,
                onPressed: () => setState(() {
                  _draft.flavor = choice;
                  _voiceHint = null;
                }),
              ),
          ],
        );

      case 1:
        return _buildChoiceStep(
          strings: strings,
          question: strings.questionSatisfaction,
          onVoiceResult: _applyVoiceRating,
          choices: [
            for (var score = 1; score <= 5; score++)
              SurveyChoiceButton(
                label: '$score',
                subLabel: strings.satisfactionLabels[score - 1],
                selected: _draft.satisfaction == score,
                onPressed: () => setState(() {
                  _draft.satisfaction = score;
                  _voiceHint = null;
                }),
              ),
          ],
        );

      case 2:
        return _buildChoiceStep(
          strings: strings,
          question: strings.questionHowHeard,
          onVoiceResult: (spoken) => _applyVoiceChoice<HowHeardChoice>(
            spoken,
            kHowHeardVoiceKeywords,
            (choice) => _draft.howHeard = choice,
          ),
          choices: [
            for (final choice in HowHeardChoice.values)
              SurveyChoiceButton(
                label: choice.label(strings),
                selected: _draft.howHeard == choice,
                onPressed: () => setState(() {
                  _draft.howHeard = choice;
                  _voiceHint = null;
                }),
              ),
          ],
        );

      case 3:
        return _buildNameStep(strings);

      default:
        return _buildEmailStep(strings);
    }
  }

  Widget _buildChoiceStep({
    required AppStrings strings,
    required String question,
    required ValueChanged<String> onVoiceResult,
    required List<Widget> choices,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildQuestionText(question),
        const SizedBox(height: 8),
        Text(
          strings.voiceHint,
          style: TextStyle(fontSize: 16, color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 16),
        VoiceCaptureButton(
          locale: widget.locale,
          strings: strings,
          onFinalResult: onVoiceResult,
        ),
        if (_voiceHint != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _voiceHint!,
              style: const TextStyle(color: Colors.red, fontSize: 16),
            ),
          ),
        const SizedBox(height: 24),
        ...choices,
      ],
    );
  }

  Widget _buildNameStep(AppStrings strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildQuestionText(strings.questionName),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 22),
                decoration: InputDecoration(
                  hintText: strings.nameFieldHint,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                ),
                onChanged: (value) => setState(() => _draft.name = value),
              ),
            ),
            const SizedBox(width: 12),
            VoiceCaptureButton(
              locale: widget.locale,
              strings: strings,
              iconOnly: true,
              onFinalResult: (spoken) {
                setState(() {
                  _nameController.text = spoken;
                  _draft.name = spoken;
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmailStep(AppStrings strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildQuestionText(strings.questionEmail),
        const SizedBox(height: 24),
        // この設問だけマイクは置かない。メールアドレスは音声認識の取り違えが多く、
        // 綴りが1文字違うだけで連絡が届かなくなるため。
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          style: const TextStyle(fontSize: 22),
          decoration: InputDecoration(
            hintText: strings.emailFieldHint,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 20,
            ),
          ),
          onChanged: (value) => setState(() {
            _draft.email = value;
            // 宛先を消したら同意も外す。届かない相手に同意だけ残らないようにする。
            if (!_draft.canConsent) _draft.consentToFollowUp = false;
          }),
        ),
        const SizedBox(height: 12),
        Text(
          strings.emailNote,
          style: TextStyle(fontSize: 14, color: Theme.of(context).hintColor),
        ),
        // 連絡先が入っていないうちは出さない。宛先の無い同意を取らないため。
        if (_draft.canConsent)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: CheckboxListTile(
              value: _draft.consentToFollowUp,
              onChanged: (checked) => setState(
                () => _draft.consentToFollowUp = checked ?? false,
              ),
              title: Text(
                strings.consentToFollowUp,
                style: const TextStyle(fontSize: 18),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const SizedBox(height: 24),
        _buildOptionalAboutYou(strings),
      ],
    );
  }

  /// 性別・年代(任意)。選ばなくても送信できる。タップし直すと選択を外せる。
  Widget _buildOptionalAboutYou(AppStrings strings) {
    Widget group<T>(
      String title,
      List<T> values,
      T? selected,
      String Function(T) label,
      ValueChanged<T?> onChanged,
    ) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final value in values)
                ChoiceChip(
                  label: Text(label(value), style: const TextStyle(fontSize: 18)),
                  selected: selected == value,
                  onSelected: (isOn) => setState(() => onChanged(isOn ? value : null)),
                ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.optionalAboutYouTitle,
          style: TextStyle(fontSize: 14, color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 12),
        group<GenderChoice>(
          strings.questionGender,
          GenderChoice.values,
          _draft.gender,
          (v) => v.label(strings),
          (v) => _draft.gender = v,
        ),
        const SizedBox(height: 16),
        group<AgeGroupChoice>(
          strings.questionAgeGroup,
          AgeGroupChoice.values,
          _draft.ageGroup,
          (v) => v.label(strings),
          (v) => _draft.ageGroup = v,
        ),
      ],
    );
  }

  Widget _buildQuestionText(String question) {
    return Text(
      question,
      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildBottomBar(AppStrings strings) {
    final isLastStep = _step == _totalSteps - 1;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: _step == 0 || _submitting ? null : _goBack,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              textStyle: const TextStyle(fontSize: 18),
            ),
            child: Text(strings.back),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _submitting || !_canAdvance ? null : _goNext,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
              textStyle: const TextStyle(fontSize: 18),
            ),
            child: Text(
              _submitting
                  ? strings.submitting
                  : (isLastStep ? strings.submit : strings.next),
            ),
          ),
        ],
      ),
    );
  }
}
