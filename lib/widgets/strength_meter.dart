import 'package:flutter/material.dart';
import '../services/strength.dart';
import '../theme/proma_palette.dart';

class StrengthMeter extends StatelessWidget {
  final String password;
  const StrengthMeter({super.key, required this.password});

  static const _colors = [
    Color(0xFFEF4444), // muito fraca
    Color(0xFFF97316), // fraca
    Color(0xFFEAB308), // razoável
    Color(0xFF84CC16), // forte
    Color(0xFF22C55E), // muito forte
  ];

  @override
  Widget build(BuildContext context) {
    final score = evaluateStrength(password);
    final active = password.isEmpty ? -1 : score;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(5, (i) {
            final on = i <= active;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == 4 ? 0 : 5),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  height: 5,
                  decoration: BoxDecoration(
                    color: on ? _colors[score] : PromaPalette.highlight,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            );
          }),
        ),
        if (password.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              strengthLabel(score),
              style: TextStyle(fontSize: 12, color: _colors[score], fontWeight: FontWeight.w500),
            ),
          ),
      ],
    );
  }
}
