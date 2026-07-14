import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../state/session_provider.dart';
import '../theme/proma_palette.dart';
import 'vault_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';

/// Largura a partir da qual usamos o layout "amplo" (barra lateral, desktop).
const double kWideBreakpoint = 720;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _index = 0;
  static const _pages = [VaultScreen(), ServersScreen(), SettingsScreen()];
  static const _titles = ['Cofre', 'Servidores', 'Configurações'];
  static const _icons = [LucideIcons.keyRound, LucideIcons.server, LucideIcons.settings];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      context.read<SessionProvider>().lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionProvider>();
    final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;
    return Listener(
      onPointerDown: (_) => session.touch(),
      onPointerSignal: (_) => session.touch(),
      child: wide ? _wideLayout(session) : _narrowLayout(session),
    );
  }

  // ---- Desktop / tela larga: barra lateral ----
  Widget _wideLayout(SessionProvider session) {
    return Scaffold(
      body: Row(children: [
        NavigationRail(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: PromaPalette.dark,
          labelType: NavigationRailLabelType.all,
          leading: const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Icon(LucideIcons.keyRound, color: PromaPalette.accent),
          ),
          trailing: Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: IconButton(
                  tooltip: 'Bloquear',
                  icon: const Icon(LucideIcons.lock, color: PromaPalette.danger),
                  onPressed: session.lock,
                ),
              ),
            ),
          ),
          destinations: [
            for (var i = 0; i < 3; i++)
              NavigationRailDestination(icon: Icon(_icons[i]), label: Text(_titles[i])),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: Padding(padding: const EdgeInsets.all(16), child: _pages[_index])),
      ]),
    );
  }

  // ---- Celular / tela estreita: AppBar + barra inferior ----
  Widget _narrowLayout(SessionProvider session) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: PromaPalette.dark,
        title: Row(children: [
          Icon(_icons[_index], size: 18, color: PromaPalette.accent),
          const SizedBox(width: 8),
          Text(_titles[_index]),
        ]),
        actions: [
          IconButton(
            tooltip: 'Bloquear',
            icon: const Icon(LucideIcons.lock, color: PromaPalette.danger),
            onPressed: session.lock,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(12), child: _pages[_index]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: PromaPalette.dark,
        indicatorColor: PromaPalette.accent.withValues(alpha: 0.25),
        destinations: const [
          NavigationDestination(icon: Icon(LucideIcons.keyRound), label: 'Cofre'),
          NavigationDestination(icon: Icon(LucideIcons.server), label: 'Servidores'),
          NavigationDestination(icon: Icon(LucideIcons.settings), label: 'Config'),
        ],
      ),
    );
  }
}
