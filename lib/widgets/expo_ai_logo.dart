import 'package:flutter/material.dart';

/// 画面上部に出す「EXPOAI」ロゴ(文字で描画。画像素材が決まったら差し替える)。
class ExpoAiLogo extends StatelessWidget {
  const ExpoAiLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'EXPOAI',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'EXPO',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: Color(0xFF14213D),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE63946),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'AI',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
