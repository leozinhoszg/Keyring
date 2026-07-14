import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'models/argon2_params.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/unlock_screen.dart';
import 'services/crypto_service.dart';
import 'services/database.dart';
import 'services/totp_service.dart';
import 'state/session_provider.dart';
import 'state/vault_provider.dart';
import 'state/vault_repository_factory.dart';
import 'theme/proma_palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openKeyringDatabase();
  final repo = createVaultRepository(db);
  final crypto = CryptoService();
  final session = SessionProvider(repo, crypto, TotpService(), const Argon2Params());
  await session.refreshStatus();
  final vault = VaultProvider(repo, crypto, () => session.dek);

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider.value(value: vault),
    ],
    child: const KeyringApp(),
  ));
}

class KeyringApp extends StatelessWidget {
  const KeyringApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Keyring',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: PromaPalette.accent,
        scaffoldBackgroundColor: PromaPalette.darkest,
        cardColor: PromaPalette.dark,
        textTheme: _keyringTextTheme(),
        colorScheme: ColorScheme.fromSeed(
          seedColor: PromaPalette.accent,
          brightness: Brightness.dark,
          surface: PromaPalette.dark,
        ),
        useMaterial3: true,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.white.withValues(alpha: 0.04),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: PromaPalette.elevated,
          isDense: false,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          hintStyle: const TextStyle(color: PromaPalette.dim),
          labelStyle: const TextStyle(color: PromaPalette.muted),
          floatingLabelStyle: const TextStyle(color: PromaPalette.accentSoft),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: PromaPalette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: PromaPalette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: PromaPalette.accent, width: 1.6),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: PromaPalette.dark,
          surfaceTintColor: Colors.transparent,
          elevation: 16,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            side: const BorderSide(color: PromaPalette.border),
            foregroundColor: PromaPalette.muted,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        checkboxTheme: CheckboxThemeData(
          side: const BorderSide(color: PromaPalette.dim, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? PromaPalette.accent : Colors.transparent,
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: PromaPalette.elevated,
          side: const BorderSide(color: PromaPalette.border),
          labelStyle: const TextStyle(fontSize: 12, color: PromaPalette.muted),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      home: const _Root(),
    );
  }
}

/// Sora (display, com caráter) nos títulos + Inter no corpo.
TextTheme _keyringTextTheme() {
  final inter = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);
  TextStyle sora(TextStyle? base, FontWeight w) =>
      GoogleFonts.sora(textStyle: base, fontWeight: w, letterSpacing: -0.2);
  return inter.copyWith(
    displayLarge: sora(inter.displayLarge, FontWeight.w800),
    displayMedium: sora(inter.displayMedium, FontWeight.w700),
    displaySmall: sora(inter.displaySmall, FontWeight.w700),
    headlineLarge: sora(inter.headlineLarge, FontWeight.w700),
    headlineMedium: sora(inter.headlineMedium, FontWeight.w700),
    headlineSmall: sora(inter.headlineSmall, FontWeight.w700),
    titleLarge: sora(inter.titleLarge, FontWeight.w700),
  );
}

class _Root extends StatelessWidget {
  const _Root();
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    if (!session.isSetup) return const SetupScreen();
    if (!session.isUnlocked) return const UnlockScreen();
    return const HomeScreen();
  }
}
