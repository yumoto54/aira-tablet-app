import 'package:flutter/material.dart';

/// 設問の選択肢1つ分。タブレットを立てたまま指で押せるよう大きめに取る。
class SurveyChoiceButton extends StatelessWidget {
  const SurveyChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.subLabel,
  });

  final String label;
  final String? subLabel;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            alignment: Alignment.centerLeft,
            backgroundColor: selected ? colors.primaryContainer : null,
            side: BorderSide(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? colors.primary : colors.outline,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                        color: colors.onSurface,
                      ),
                    ),
                    if (subLabel != null)
                      Text(
                        subLabel!,
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
