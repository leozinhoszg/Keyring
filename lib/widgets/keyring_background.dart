import 'package:flutter/material.dart';
import '../screens/home_screen.dart' show kWideBreakpoint;
import '../theme/proma_palette.dart';

/// Fundo com o wallpaper Steel & Gold (responsivo mobile/desktop) + um scrim
/// grafite e vinheta por cima, garantindo legibilidade do conteúdo.
class KeyringBackground extends StatelessWidget {
  final Widget child;

  /// Opacidade do grafite sobre o wallpaper (0 = wallpaper puro, 1 = grafite sólido).
  final double scrim;
  const KeyringBackground({super.key, required this.child, this.scrim = 0.55});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;
    final img = wide ? 'assets/bg_desktop.png' : 'assets/bg_mobile.png';
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(img, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
        // scrim vertical para legibilidade
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                PromaPalette.darkest.withValues(alpha: (scrim + 0.15).clamp(0, 1)),
                PromaPalette.darkest.withValues(alpha: scrim),
              ],
            ),
          ),
        ),
        // vinheta radial (foco no centro)
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.15,
              colors: [Colors.transparent, PromaPalette.darkest.withValues(alpha: 0.45)],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
