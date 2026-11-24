import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../l10n/app_strings.dart';
import 'game_api.dart';

/// 絵柄(サーバーが返す 0〜4 に対応)。店のロゴ画像に差し替えるときはここを変える。
const List<String> kSlotSymbols = ['🥞', '🍓', '🍌', '🍫', '🍦'];

/// 来場者向けスロット。「SPIN」を押すとサーバーで抽選し、結果の絵柄で3つのリールが順に止まる。
/// 当たるとクーポンコードを大きく出す(スタッフがコードを確認して景品を渡す)。
class SlotGamePage extends StatefulWidget {
  const SlotGamePage({super.key, required this.locale});

  final AppLocale locale;

  @override
  State<SlotGamePage> createState() => _SlotGamePageState();
}

enum _Phase { ready, spinning, done, limit, error }

class _SlotGamePageState extends State<SlotGamePage> {
  final _random = Random();
  final List<int> _shown = [0, 1, 2];
  _Phase _phase = _Phase.ready;
  SpinResult? _result;
  Timer? _ticker;
  final List<bool> _stopped = [false, false, false];

  AppStrings get _s => AppStrings.of(widget.locale);

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _spin() async {
    if (_phase == _Phase.spinning) return;
    setState(() {
      _phase = _Phase.spinning;
      _result = null;
      for (var i = 0; i < 3; i++) {
        _stopped[i] = false;
      }
    });

    // 回っている間は絵柄をランダムに切り替え続ける(見た目だけ。結果とは無関係)
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < 3; i++) {
          if (!_stopped[i]) _shown[i] = _random.nextInt(kSlotSymbols.length);
        }
      });
    });

    final outcome = await spinSlot(locale: widget.locale);
    if (!mounted) return;

    switch (outcome) {
      case SpinLimitReached():
        _ticker?.cancel();
        setState(() => _phase = _Phase.limit);
      case SpinFailed():
        _ticker?.cancel();
        setState(() => _phase = _Phase.error);
      case SpinOk(:final result):
        // 左から順に、少し間を置いて止める
        for (var i = 0; i < 3; i++) {
          await Future<void>.delayed(Duration(milliseconds: i == 0 ? 700 : 600));
          if (!mounted) return;
          setState(() {
            _stopped[i] = true;
            _shown[i] = result.reels[i].clamp(0, kSlotSymbols.length - 1);
          });
        }
        _ticker?.cancel();
        setState(() {
          _result = result;
          _phase = _Phase.done;
        });
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _reel(int i) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 150,
      height: 170,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.primary, width: 4),
      ),
      child: Text(kSlotSymbols[_shown[i]], style: const TextStyle(fontSize: 96)),
    );
  }

  Widget _message(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final r = _result;
    switch (_phase) {
      case _Phase.ready:
        return const SizedBox(height: 120);
      case _Phase.spinning:
        return SizedBox(
          height: 120,
          child: Center(child: Text(_s.gameSpinning, style: const TextStyle(fontSize: 28))),
        );
      case _Phase.limit:
        return Text(_s.gameLimit, textAlign: TextAlign.center, style: const TextStyle(fontSize: 28));
      case _Phase.error:
        return Text(_s.gameError, textAlign: TextAlign.center, style: const TextStyle(fontSize: 28));
      case _Phase.done:
        if (r == null) return const SizedBox.shrink();
        if (!r.isWin) {
          return Column(children: [
            Text(_s.gameMiss, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_s.gamePlaysLeft(r.playsLeft), style: TextStyle(fontSize: 20, color: colors.onSurfaceVariant)),
          ]);
        }
        return Column(children: [
          Text(
            r.result == 'jackpot' ? _s.gameJackpot : _s.gameSmall,
            style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: colors.primary),
          ),
          if (r.prizeLabel != null)
            Text(r.prizeLabel!, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              r.couponCode ?? '',
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: colors.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(_s.gameShowStaff, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20)),
          if (r.expiresAt != null)
            Text(_s.gameExpires(_formatDate(r.expiresAt!)),
                style: TextStyle(fontSize: 18, color: colors.onSurfaceVariant)),
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSpin = _phase == _Phase.ready || _phase == _Phase.done || _phase == _Phase.error;
    return Scaffold(
      appBar: AppBar(title: Text(_s.gameTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 16),
                      _reel(i),
                    ],
                  ],
                ),
                const SizedBox(height: 32),
                _message(context),
                const SizedBox(height: 32),
                if (_phase != _Phase.limit)
                  FilledButton(
                    onPressed: canSpin ? _spin : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 72, vertical: 24),
                      textStyle: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                    child: Text(_s.gameSpin),
                  ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(_s.close, style: const TextStyle(fontSize: 20)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
