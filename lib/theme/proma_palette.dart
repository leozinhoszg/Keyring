import 'package:flutter/material.dart';

/// Paleta da identidade "Steel & Gold" do Keyring.
/// (Nome da classe mantido por compatibilidade com os widgets existentes.)
class PromaPalette {
  // Grafite / aço — camadas de profundidade
  static const Color darkest = Color(0xFF0A0C0F); // abyss / fundo profundo
  static const Color base = Color(0xFF101318); // fundo do app
  static const Color dark = Color(0xFF171B21); // surface (cards, rail, appbar)
  static const Color elevated = Color(0xFF1E242C); // cards elevados
  static const Color highlight = Color(0xFF262D36); // raised / hover
  static const Color border = Color(0xFF2C343E); // linhas/divisórias
  static const Color borderStrong = Color(0xFF3B4551); // reflexo metálico

  // Ouro — accent (o "cadeado")
  static const Color accent = Color(0xFFC9A24B); // ouro fosco (ação/foco)
  static const Color accentSoft = Color(0xFFE7C86A); // ouro brilho / hover
  static const Color accentGlow = Color(0xFFE7C86A);
  static const Color goldDeep = Color(0xFF8F6F2A); // sombra do ouro

  // Texto (prata)
  static const Color white = Color(0xFFECEFF3); // texto principal
  static const Color muted = Color(0xFFAEB6C0); // texto secundário
  static const Color dim = Color(0xFF6C7681); // texto sutil

  // Semânticos
  static const Color danger = Color(0xFFE5555B);
  static const Color warning = Color(0xFFE0A83B); // âmbar (harmoniza com o ouro)
  static const Color success = Color(0xFF4FB477);

  // Ouro polido (botões primários, detalhes do logo)
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFF3E3A6), Color(0xFFCBA24B), Color(0xFF8A6A26)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
