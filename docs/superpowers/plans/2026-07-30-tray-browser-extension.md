# Bandeja do sistema + extensão de navegador — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deixar o keyring residente na bandeja do Windows e permitir que uma extensão Chrome/Edge ofereça salvar logins digitados em sites diretamente no cofre.

**Architecture:** O app Flutter ganha um `TrayService` (bandeja + esconder no X), auto-início com o Windows e um `BridgeServer` WebSocket em `127.0.0.1` (portas 19457–19459) que só aceita operações de escrita autenticadas por token de pareamento. Uma extensão MV3 em `browser-extension/` captura submissões de formulários de login, guarda a captura por aba e, na página seguinte, mostra um banner "Salvar no keyring?"; ao aceitar, envia via WebSocket. Um `BrowserSaveCoordinator` decide entre salvar direto (cofre aberto) ou restaurar a janela e esperar o desbloqueio.

**Tech Stack:** Flutter/Dart (pacotes `tray_manager`, `window_manager`, `launch_at_startup`, `flutter_secure_storage` já existente, `dart:io` para o WebSocket), extensão em JavaScript puro (Manifest V3, `chrome.storage.session/local`).

**Spec:** `docs/superpowers/specs/2026-07-29-tray-browser-extension-design.md`

## Global Constraints

- Recursos novos (bandeja, auto-início, bridge) só ativam no Windows: guardar com `Platform.isWindows`. Demais plataformas seguem como antes.
- Portas do bridge, nesta ordem exata: `19457`, `19458`, `19459` — mesmas no app e na extensão.
- O servidor **nunca** envia segredos do cofre: as únicas respostas são `pair-result` e `save-result`.
- Somente salvar (criar credencial nova). Autofill, atualização e dedupe estão fora do escopo.
- Extensão: Chrome/Edge ≥ 116 (necessário para o WebSocket manter o service worker MV3 vivo durante a espera do desbloqueio).
- Todo texto de UI em português, com acentuação correta.
- A árvore de trabalho tem mudanças NÃO COMMITADAS de outro trabalho (ex.: `lib/screens/settings_screen.dart`, `lib/state/*`). Commits desta feature usam `git add` explícito por arquivo, nunca `git add -A`. Antes de modificar um arquivo que aparece como `M` no `git status`, rodar `git diff -- <arquivo>` e, se houver diff substantivo (não só fim de linha), PARAR e perguntar ao usuário como proceder.
- Rodar `flutter analyze` antes de cada commit; zero erros novos.

---

## Fase A — Bandeja e auto-início

### Task 1: TrayService + esconder no X + `--hidden`

**Files:**
- Modify: `pubspec.yaml` (via `flutter pub add`)
- Create: `assets/tray_icon.ico` (cópia de `windows/runner/resources/app_icon.ico`)
- Create: `lib/services/tray_service.dart`
- Modify: `lib/main.dart`
- Modify: `windows/runner/flutter_window.cpp`

**Interfaces:**
- Produces: `class TrayService with TrayListener, WindowListener` com construtor `TrayService({required void Function() onLock})`, métodos `Future<void> init()`, `Future<void> showWindow()`, `void dispose()`. Task 6 usa `showWindow()` para restaurar a janela.
- Produces: `final navigatorKey = GlobalKey<NavigatorState>()` (top-level em `lib/main.dart`) — Task 6 usa para exibir o diálogo de pareamento.

- [ ] **Step 1: Adicionar dependências e o ícone da bandeja**

```powershell
flutter pub add tray_manager window_manager launch_at_startup
Copy-Item windows/runner/resources/app_icon.ico assets/tray_icon.ico
```

`pubspec.yaml` já inclui `assets/` inteiro, então o `.ico` entra sem mudança extra.

- [ ] **Step 2: Criar `lib/services/tray_service.dart`**

```dart
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Mantém o app vivo na bandeja: o X esconde a janela; sair de verdade só
/// pelo menu do ícone.
class TrayService with TrayListener, WindowListener {
  TrayService({required this.onLock});

  /// Chamado pelo item "Bloquear cofre" do menu da bandeja.
  final void Function() onLock;

  static const _menuShow = 'show';
  static const _menuLock = 'lock';
  static const _menuExit = 'exit';

  Future<void> init() async {
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    await trayManager.setIcon('assets/tray_icon.ico');
    await trayManager.setToolTip('Keyring');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: _menuShow, label: 'Abrir keyring'),
      MenuItem(key: _menuLock, label: 'Bloquear cofre'),
      MenuItem.separator(),
      MenuItem(key: _menuExit, label: 'Sair'),
    ]));
    trayManager.addListener(this);
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onWindowClose() {
    windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() {
    showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem item) async {
    switch (item.key) {
      case _menuShow:
        await showWindow();
      case _menuLock:
        onLock();
      case _menuExit:
        await trayManager.destroy();
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
    }
  }

  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
  }
}
```

- [ ] **Step 3: Integrar no `lib/main.dart`**

Assinatura do `main` passa a receber os argumentos e a inicializar janela/bandeja no
Windows. Trechos a alterar (o restante do arquivo fica como está):

```dart
import 'dart:io' show Platform;

import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:window_manager/window_manager.dart';

import 'services/tray_service.dart';

/// Task 6 usa esta key para abrir o diálogo de pareamento fora da árvore de telas.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final isWindows = !kIsWeb && Platform.isWindows;
  if (isWindows) {
    await windowManager.ensureInitialized();
    launchAtStartup.setup(
      appName: 'Keyring',
      appPath: Platform.resolvedExecutable,
      args: ['--hidden'],
    );
  }
  try {
    // ... bootstrap existente (db, repo, crypto, session, vault) ...

    if (isWindows) {
      final tray = TrayService(onLock: () {
        session.lock();
        vault.clearCache();
      });
      await tray.init();
      final startHidden = args.contains('--hidden');
      if (!startHidden) {
        await windowManager.waitUntilReadyToShow(null, () async {
          await windowManager.show();
          await windowManager.focus();
        });
      }
    }

    runApp(/* MultiProvider existente */);
  } catch (e, s) {
    runApp(BootErrorApp(error: '$e', stack: '$s'));
  }
}
```

`kIsWeb` vem de `package:flutter/foundation.dart` (já reexportado por material).
No `KeyringApp`, adicionar `navigatorKey: navigatorKey` ao `MaterialApp`.

- [ ] **Step 4: Runner nativo respeitar `--hidden`**

Em `windows/runner/flutter_window.cpp`, o template mostra a janela no primeiro
frame. Trocar o corpo do callback para só mostrar quando NÃO houver `--hidden`
(assim um erro de bootstrap continua visível em inicialização normal):

```cpp
  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (wcsstr(::GetCommandLineW(), L"--hidden") == nullptr) {
      this->Show();
    }
  });
```

- [ ] **Step 5: Verificar**

Run: `flutter analyze` — esperado: sem erros novos.
Run: `flutter run -d windows` e conferir manualmente:
1. Ícone do keyring aparece na bandeja com tooltip "Keyring".
2. Clicar no X: janela some, processo continua (ícone segue na bandeja).
3. Clique esquerdo no ícone: janela volta. Clique direito: menu com Abrir/Bloquear/Sair.
4. "Bloquear cofre": ao reabrir a janela, tela de desbloqueio.
5. "Sair": processo encerra de verdade.
6. `flutter run -d windows` de novo; depois testar o exe compilado com `--hidden`
   (build/windows/x64/runner/Debug/keyring.exe --hidden): inicia sem janela, só bandeja.

- [ ] **Step 6: Commit**

```powershell
git add pubspec.yaml pubspec.lock assets/tray_icon.ico lib/services/tray_service.dart lib/main.dart windows/runner/flutter_window.cpp
git commit -m "feat: app residente na bandeja do sistema (fechar esconde, --hidden)"
```

Se o `flutter pub add` também tocar `windows/flutter/generated_plugin*` e
`linux/`/`macos/` equivalentes, incluí-los no add (são gerados, precisam ir junto).

### Task 2: Toggle "Iniciar com o Windows" nas Configurações

**Files:**
- Modify: `lib/screens/settings_screen.dart` (card "Segurança", após o SwitchListTile do acesso rápido, ~linha 186)

**Interfaces:**
- Consumes: `launchAtStartup` já configurado com `setup(...)` no `main` (Task 1).

- [ ] **Step 1: Conferir estado do arquivo**

Run: `git diff -- lib/screens/settings_screen.dart`
Se houver diff substantivo de outro trabalho, PARAR e perguntar ao usuário.

- [ ] **Step 2: Adicionar o toggle**

No `_SettingsScreenState`:

```dart
bool _startsWithWindows = false;

@override
void initState() {
  super.initState(); // manter o que já existir no initState atual
  _loadStartup();
}

Future<void> _loadStartup() async {
  if (!Platform.isWindows) return;
  final enabled = await launchAtStartup.isEnabled();
  if (mounted) setState(() => _startsWithWindows = enabled);
}

Future<void> _toggleStartup(bool value) async {
  if (value) {
    await launchAtStartup.enable();
  } else {
    await launchAtStartup.disable();
  }
  await _loadStartup();
}
```

Import: `package:launch_at_startup/launch_at_startup.dart` (o arquivo já importa `dart:io`).
No card "Segurança", logo após o `SwitchListTile` do acesso rápido:

```dart
if (Platform.isWindows)
  SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: const Text('Iniciar com o Windows'),
    subtitle: const Text('Abre já minimizado na bandeja, para a integração com o navegador funcionar sempre'),
    value: _startsWithWindows,
    onChanged: _toggleStartup,
  ),
```

- [ ] **Step 3: Verificar**

Run: `flutter analyze` — sem erros novos.
Run: `flutter run -d windows`: ligar o toggle e conferir a chave criada em
`HKCU:\Software\Microsoft\Windows\CurrentVersion\Run` (nome `Keyring`, com `--hidden`):

```powershell
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' | Select-Object Keyring
```

Desligar o toggle e conferir que a chave some.

- [ ] **Step 4: Commit**

```powershell
git add lib/screens/settings_screen.dart
git commit -m "feat: opcao de iniciar com o Windows minimizado na bandeja"
```

---

## Fase B — Servidor local e fluxo de salvamento

### Task 3: Protocolo do bridge (mensagens JSON + token + título)

**Files:**
- Create: `lib/services/browser_bridge/protocol.dart`
- Test: `test/browser_bridge_protocol_test.dart`

**Interfaces:**
- Produces (usadas pelas Tasks 4–6):
  - `class SaveRequest { final String url; final String username; final String password; }`
  - `enum SaveStatus { ok, cancelled, invalidToken, busy, error }`
  - `sealed class BridgeMessage` com `static BridgeMessage? decode(String raw)`
  - `class PairMessage extends BridgeMessage { final String client; }`
  - `class SaveMessage extends BridgeMessage { final String token; final SaveRequest request; }`
  - `String encodePairResult({required bool ok, String? token})`
  - `String encodeSaveResult(SaveStatus status)`
  - `String generatePairingToken()`
  - `String titleFromUrl(String url)`

- [ ] **Step 1: Escrever os testes (falhando)**

`test/browser_bridge_protocol_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keyring/services/browser_bridge/protocol.dart';

void main() {
  group('BridgeMessage.decode', () {
    test('decodifica pair', () {
      final m = BridgeMessage.decode('{"type":"pair","client":"ext"}');
      expect(m, isA<PairMessage>());
      expect((m as PairMessage).client, 'ext');
    });

    test('decodifica save', () {
      final m = BridgeMessage.decode(jsonEncode({
        'type': 'save',
        'token': 't1',
        'url': 'https://ex.com/login',
        'username': 'ana',
        'password': 's3nh4',
      }));
      expect(m, isA<SaveMessage>());
      final save = m as SaveMessage;
      expect(save.token, 't1');
      expect(save.request.url, 'https://ex.com/login');
      expect(save.request.username, 'ana');
      expect(save.request.password, 's3nh4');
    });

    test('rejeita lixo, tipo desconhecido e campos faltando', () {
      expect(BridgeMessage.decode('não é json'), isNull);
      expect(BridgeMessage.decode('"string json"'), isNull);
      expect(BridgeMessage.decode('{"type":"outro"}'), isNull);
      expect(BridgeMessage.decode('{"type":"pair"}'), isNull);
      expect(BridgeMessage.decode('{"type":"save","token":"t"}'), isNull);
      expect(
          BridgeMessage.decode(jsonEncode({
            'type': 'save', 'token': 't', 'url': '', 'username': 'a', 'password': 'p',
          })),
          isNull);
      expect(
          BridgeMessage.decode(jsonEncode({
            'type': 'save', 'token': 't', 'url': 'https://x', 'username': 'a', 'password': '',
          })),
          isNull);
    });
  });

  test('encodePairResult / encodeSaveResult', () {
    expect(jsonDecode(encodePairResult(ok: true, token: 'abc')),
        {'type': 'pair-result', 'ok': true, 'token': 'abc'});
    expect(jsonDecode(encodePairResult(ok: false)), {'type': 'pair-result', 'ok': false});
    expect(jsonDecode(encodeSaveResult(SaveStatus.ok)), {'type': 'save-result', 'status': 'ok'});
    expect(jsonDecode(encodeSaveResult(SaveStatus.invalidToken)),
        {'type': 'save-result', 'status': 'invalid-token'});
    expect(jsonDecode(encodeSaveResult(SaveStatus.cancelled)),
        {'type': 'save-result', 'status': 'cancelled'});
    expect(jsonDecode(encodeSaveResult(SaveStatus.busy)), {'type': 'save-result', 'status': 'busy'});
    expect(jsonDecode(encodeSaveResult(SaveStatus.error)), {'type': 'save-result', 'status': 'error'});
  });

  test('generatePairingToken: 32 bytes base64url, sempre diferente', () {
    final a = generatePairingToken();
    final b = generatePairingToken();
    expect(a, isNot(b));
    expect(base64Url.decode(a).length, 32);
  });

  group('titleFromUrl', () {
    test('host sem www', () {
      expect(titleFromUrl('https://www.github.com/login'), 'github.com');
      expect(titleFromUrl('https://conta.example.com.br/entrar?x=1'), 'conta.example.com.br');
    });
    test('sem host cai para a string original', () {
      expect(titleFromUrl('coisa qualquer'), 'coisa qualquer');
    });
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/browser_bridge_protocol_test.dart`
Expected: falha de compilação — `protocol.dart` não existe.

- [ ] **Step 3: Implementar `lib/services/browser_bridge/protocol.dart`**

```dart
import 'dart:convert';
import 'dart:math';

/// Pedido de salvamento vindo da extensão de navegador.
class SaveRequest {
  final String url;
  final String username;
  final String password;
  const SaveRequest({required this.url, required this.username, required this.password});
}

/// Desfecho de um pedido de salvamento, na ordem em que a extensão os trata.
enum SaveStatus { ok, cancelled, invalidToken, busy, error }

/// Mensagens que a extensão pode mandar. O protocolo é só de escrita:
/// nenhuma resposta carrega segredos do cofre.
sealed class BridgeMessage {
  const BridgeMessage();

  /// Retorna null para JSON malformado, tipo desconhecido ou campos inválidos.
  static BridgeMessage? decode(String raw) {
    final Object? data;
    try {
      data = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (data is! Map<String, Object?>) return null;
    switch (data['type']) {
      case 'pair':
        final client = data['client'];
        if (client is! String || client.isEmpty) return null;
        return PairMessage(client: client);
      case 'save':
        final token = data['token'];
        final url = data['url'];
        final username = data['username'];
        final password = data['password'];
        if (token is! String || url is! String || username is! String || password is! String) {
          return null;
        }
        if (url.isEmpty || password.isEmpty) return null;
        return SaveMessage(
          token: token,
          request: SaveRequest(url: url, username: username, password: password),
        );
    }
    return null;
  }
}

class PairMessage extends BridgeMessage {
  final String client;
  const PairMessage({required this.client});
}

class SaveMessage extends BridgeMessage {
  final String token;
  final SaveRequest request;
  const SaveMessage({required this.token, required this.request});
}

String encodePairResult({required bool ok, String? token}) =>
    jsonEncode({'type': 'pair-result', 'ok': ok, if (token != null) 'token': token});

String encodeSaveResult(SaveStatus status) => jsonEncode({
      'type': 'save-result',
      'status': switch (status) {
        SaveStatus.ok => 'ok',
        SaveStatus.cancelled => 'cancelled',
        SaveStatus.invalidToken => 'invalid-token',
        SaveStatus.busy => 'busy',
        SaveStatus.error => 'error',
      },
    });

/// 32 bytes do gerador seguro do SO, em base64url.
String generatePairingToken() {
  final rnd = Random.secure();
  return base64UrlEncode(List<int>.generate(32, (_) => rnd.nextInt(256)));
}

/// Título sugerido para a credencial: host sem o prefixo `www.`.
/// Cai para a própria string quando não dá para extrair um host.
String titleFromUrl(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isEmpty) return url;
  return host.startsWith('www.') ? host.substring(4) : host;
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/browser_bridge_protocol_test.dart`
Expected: todos passam. Rodar também `flutter analyze`.

- [ ] **Step 5: Commit**

```powershell
git add lib/services/browser_bridge/protocol.dart test/browser_bridge_protocol_test.dart
git commit -m "feat: protocolo do bridge navegador-cofre (mensagens, token, titulo)"
```

### Task 4: PairingStore + BridgeServer WebSocket

**Files:**
- Create: `lib/services/browser_bridge/pairing_store.dart`
- Create: `lib/services/browser_bridge/bridge_server.dart`
- Test: `test/bridge_server_test.dart`

**Interfaces:**
- Consumes: tudo de `protocol.dart` (Task 3).
- Produces:
  - `abstract class PairingStore { Future<String?> read(); Future<void> write(String token); }`
  - `class SecurePairingStore implements PairingStore` (usa `FlutterSecureStorage`, chave `browser_bridge_token`)
  - `class InMemoryPairingStore implements PairingStore` (para testes e para a Task 5)
  - `class BridgeServer` com construtor `BridgeServer({required PairingStore pairingStore, required Future<bool> Function(String client) onPairRequest, required Future<SaveStatus> Function(SaveRequest request) onSave})`, `static const ports = [19457, 19458, 19459]`, `Future<int?> start()`, `Future<void> stop()`, `int? get port`.

- [ ] **Step 1: Escrever os testes (falhando)**

`test/bridge_server_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keyring/services/browser_bridge/bridge_server.dart';
import 'package:keyring/services/browser_bridge/pairing_store.dart';
import 'package:keyring/services/browser_bridge/protocol.dart';

Future<Map<String, dynamic>> roundtrip(int port, Map<String, dynamic> msg) async {
  final ws = await WebSocket.connect('ws://127.0.0.1:$port');
  ws.add(jsonEncode(msg));
  final reply = jsonDecode(await ws.first as String) as Map<String, dynamic>;
  await ws.close();
  return reply;
}

void main() {
  test('pareamento aprovado gera token e persiste', () async {
    final store = InMemoryPairingStore();
    final server = BridgeServer(
      pairingStore: store,
      onPairRequest: (client) async => client == 'ext-ok',
      onSave: (_) async => SaveStatus.ok,
    );
    final port = await server.start();
    expect(port, isNotNull);

    final reply = await roundtrip(port!, {'type': 'pair', 'client': 'ext-ok'});
    expect(reply['ok'], isTrue);
    expect(reply['token'], isNotEmpty);
    expect(await store.read(), reply['token']);
    await server.stop();
  });

  test('pareamento negado não grava token', () async {
    final store = InMemoryPairingStore();
    final server = BridgeServer(
      pairingStore: store,
      onPairRequest: (_) async => false,
      onSave: (_) async => SaveStatus.ok,
    );
    final port = await server.start();
    final reply = await roundtrip(port!, {'type': 'pair', 'client': 'x'});
    expect(reply['ok'], isFalse);
    expect(reply.containsKey('token'), isFalse);
    expect(await store.read(), isNull);
    await server.stop();
  });

  test('save com token válido chama o handler; inválido não', () async {
    final store = InMemoryPairingStore();
    await store.write('tok-1');
    SaveRequest? received;
    final server = BridgeServer(
      pairingStore: store,
      onPairRequest: (_) async => false,
      onSave: (r) async {
        received = r;
        return SaveStatus.ok;
      },
    );
    final port = await server.start();

    final ok = await roundtrip(port!, {
      'type': 'save', 'token': 'tok-1',
      'url': 'https://ex.com', 'username': 'ana', 'password': 'p',
    });
    expect(ok['status'], 'ok');
    expect(received!.username, 'ana');

    final bad = await roundtrip(port, {
      'type': 'save', 'token': 'errado',
      'url': 'https://ex.com', 'username': 'ana', 'password': 'p',
    });
    expect(bad['status'], 'invalid-token');
    await server.stop();
  });

  test('mensagem malformada responde error', () async {
    final server = BridgeServer(
      pairingStore: InMemoryPairingStore(),
      onPairRequest: (_) async => false,
      onSave: (_) async => SaveStatus.ok,
    );
    final port = await server.start();
    final reply = await roundtrip(port!, {'type': 'outra-coisa'});
    expect(reply['status'], 'error');
    await server.stop();
  });

  test('porta ocupada: usa a próxima da lista', () async {
    final blocker = await ServerSocket.bind(InternetAddress.loopbackIPv4, BridgeServer.ports.first);
    final server = BridgeServer(
      pairingStore: InMemoryPairingStore(),
      onPairRequest: (_) async => false,
      onSave: (_) async => SaveStatus.ok,
    );
    final port = await server.start();
    expect(port, BridgeServer.ports[1]);
    await server.stop();
    await blocker.close();
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/bridge_server_test.dart`
Expected: falha de compilação — arquivos não existem.

- [ ] **Step 3: Implementar `pairing_store.dart`**

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda o token que autentica a extensão pareada.
abstract class PairingStore {
  Future<String?> read();
  Future<void> write(String token);
}

class SecurePairingStore implements PairingStore {
  static const _key = 'browser_bridge_token';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);
}

/// Para testes e composição sem tocar o keystore do SO.
class InMemoryPairingStore implements PairingStore {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;
}
```

- [ ] **Step 4: Implementar `bridge_server.dart`**

```dart
import 'dart:io';

import 'pairing_store.dart';
import 'protocol.dart';

/// Servidor WebSocket local para a extensão de navegador. Só escrita:
/// as únicas respostas possíveis são pair-result e save-result.
class BridgeServer {
  static const ports = [19457, 19458, 19459];

  BridgeServer({
    required this.pairingStore,
    required this.onPairRequest,
    required this.onSave,
  });

  final PairingStore pairingStore;

  /// Decide o pareamento — na prática, mostra o diálogo "permitir?" no app.
  final Future<bool> Function(String client) onPairRequest;

  /// Executa o salvamento — na prática, o BrowserSaveCoordinator.
  final Future<SaveStatus> Function(SaveRequest request) onSave;

  HttpServer? _server;
  bool _busy = false;

  int? get port => _server?.port;

  /// Tenta as portas em ordem. Null = todas ocupadas (bridge fica desligado).
  Future<int?> start() async {
    for (final p in ports) {
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, p);
      } on SocketException {
        continue;
      }
      _server!.listen(_handleHttp);
      return p;
    }
    return null;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleHttp(HttpRequest req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response
        ..statusCode = HttpStatus.badRequest
        ..close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    ws.listen((raw) {
      if (raw is String) _handleMessage(ws, raw);
    });
  }

  Future<void> _handleMessage(WebSocket ws, String raw) async {
    switch (BridgeMessage.decode(raw)) {
      case PairMessage(:final client):
        final approved = await onPairRequest(client);
        if (!approved) {
          ws.add(encodePairResult(ok: false));
          return;
        }
        final token = generatePairingToken();
        await pairingStore.write(token);
        ws.add(encodePairResult(ok: true, token: token));
      case SaveMessage(:final token, :final request):
        final expected = await pairingStore.read();
        if (expected == null || token != expected) {
          ws.add(encodeSaveResult(SaveStatus.invalidToken));
          return;
        }
        if (_busy) {
          ws.add(encodeSaveResult(SaveStatus.busy));
          return;
        }
        _busy = true;
        try {
          ws.add(encodeSaveResult(await onSave(request)));
        } catch (_) {
          ws.add(encodeSaveResult(SaveStatus.error));
        } finally {
          _busy = false;
        }
      case null:
        ws.add(encodeSaveResult(SaveStatus.error));
    }
  }
}
```

- [ ] **Step 5: Rodar e ver passar**

Run: `flutter test test/bridge_server_test.dart`
Expected: todos passam. Rodar `flutter analyze`.

- [ ] **Step 6: Commit**

```powershell
git add lib/services/browser_bridge/pairing_store.dart lib/services/browser_bridge/bridge_server.dart test/bridge_server_test.dart
git commit -m "feat: servidor WebSocket local com pareamento por token"
```

### Task 5: BrowserSaveCoordinator (salvar já ou esperar desbloqueio)

**Files:**
- Create: `lib/state/browser_save_coordinator.dart`
- Test: `test/browser_save_coordinator_test.dart`

**Interfaces:**
- Consumes: `SaveRequest`, `SaveStatus`, `titleFromUrl` (Task 3); `CredentialInput` (`lib/models/credential.dart`).
- Produces: `class BrowserSaveCoordinator` com construtor `BrowserSaveCoordinator({required Listenable sessionListenable, required bool Function() isUnlocked, required Future<void> Function(CredentialInput input) createCredential, void Function()? onNeedUnlock, Duration unlockTimeout = const Duration(minutes: 2)})` e método `Future<SaveStatus> handleSave(SaveRequest req)` — a Task 6 pluga este método no `onSave` do `BridgeServer`.

- [ ] **Step 1: Escrever os testes (falhando)**

`test/browser_save_coordinator_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyring/models/credential.dart';
import 'package:keyring/services/browser_bridge/protocol.dart';
import 'package:keyring/state/browser_save_coordinator.dart';

void main() {
  const req = SaveRequest(url: 'https://www.ex.com/login', username: 'ana', password: 'p1');

  test('cofre aberto: salva direto com título do domínio', () async {
    final saved = <CredentialInput>[];
    final c = BrowserSaveCoordinator(
      sessionListenable: ChangeNotifier(),
      isUnlocked: () => true,
      createCredential: (i) async => saved.add(i),
    );
    expect(await c.handleSave(req), SaveStatus.ok);
    expect(saved.single.title, 'ex.com');
    expect(saved.single.username, 'ana');
    expect(saved.single.password, 'p1');
    expect(saved.single.url, 'https://www.ex.com/login');
  });

  test('cofre travado: pede janela, espera desbloqueio e salva', () async {
    final saved = <CredentialInput>[];
    var unlocked = false;
    var askedWindow = false;
    final session = ValueNotifier(0);
    final c = BrowserSaveCoordinator(
      sessionListenable: session,
      isUnlocked: () => unlocked,
      createCredential: (i) async => saved.add(i),
      onNeedUnlock: () => askedWindow = true,
    );
    final future = c.handleSave(req);
    await Future<void>.delayed(Duration.zero);
    expect(askedWindow, isTrue);
    expect(saved, isEmpty);

    unlocked = true;
    session.value = 1; // notifica
    expect(await future, SaveStatus.ok);
    expect(saved, hasLength(1));
  });

  test('travado sem desbloquear no prazo: cancelled e nada salvo', () async {
    final saved = <CredentialInput>[];
    final c = BrowserSaveCoordinator(
      sessionListenable: ChangeNotifier(),
      isUnlocked: () => false,
      createCredential: (i) async => saved.add(i),
      unlockTimeout: const Duration(milliseconds: 50),
    );
    expect(await c.handleSave(req), SaveStatus.cancelled);
    expect(saved, isEmpty);
  });

  test('username vazio vira null; erro do repositório vira error', () async {
    CredentialInput? got;
    final ok = BrowserSaveCoordinator(
      sessionListenable: ChangeNotifier(),
      isUnlocked: () => true,
      createCredential: (i) async => got = i,
    );
    await ok.handleSave(const SaveRequest(url: 'https://x.com', username: '', password: 'p'));
    expect(got!.username, isNull);

    final failing = BrowserSaveCoordinator(
      sessionListenable: ChangeNotifier(),
      isUnlocked: () => true,
      createCredential: (_) async => throw StateError('boom'),
    );
    expect(await failing.handleSave(req), SaveStatus.error);
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/browser_save_coordinator_test.dart`
Expected: falha de compilação.

- [ ] **Step 3: Implementar `lib/state/browser_save_coordinator.dart`**

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/credential.dart';
import '../services/browser_bridge/protocol.dart';

/// Liga o BridgeServer ao cofre: com o cofre aberto salva na hora; travado,
/// traz a janela à frente e espera o desbloqueio (ou desiste no timeout).
class BrowserSaveCoordinator {
  BrowserSaveCoordinator({
    required this.sessionListenable,
    required this.isUnlocked,
    required this.createCredential,
    this.onNeedUnlock,
    this.unlockTimeout = const Duration(minutes: 2),
  });

  final Listenable sessionListenable;
  final bool Function() isUnlocked;
  final Future<void> Function(CredentialInput input) createCredential;

  /// Chamado quando o salvamento precisa da janela visível para desbloquear.
  final void Function()? onNeedUnlock;
  final Duration unlockTimeout;

  Future<SaveStatus> handleSave(SaveRequest req) async {
    if (!isUnlocked()) {
      onNeedUnlock?.call();
      if (!await _waitForUnlock()) return SaveStatus.cancelled;
    }
    try {
      await createCredential(CredentialInput(
        title: titleFromUrl(req.url),
        username: req.username.isEmpty ? null : req.username,
        password: req.password,
        url: req.url,
      ));
      return SaveStatus.ok;
    } catch (_) {
      return SaveStatus.error;
    }
  }

  Future<bool> _waitForUnlock() {
    final completer = Completer<bool>();
    void listener() {
      if (isUnlocked() && !completer.isCompleted) completer.complete(true);
    }

    sessionListenable.addListener(listener);
    final timer = Timer(unlockTimeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });
    return completer.future.whenComplete(() {
      timer.cancel();
      sessionListenable.removeListener(listener);
    });
  }
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/browser_save_coordinator_test.dart`
Expected: todos passam. Rodar `flutter analyze` e a suíte inteira: `flutter test`.

- [ ] **Step 5: Commit**

```powershell
git add lib/state/browser_save_coordinator.dart test/browser_save_coordinator_test.dart
git commit -m "feat: coordenador de salvamento vindo do navegador"
```

### Task 6: Ligar o bridge no app (diálogo de pareamento + janela no desbloqueio)

**Files:**
- Modify: `lib/main.dart`
- Create: `tool/bridge_smoke.dart` (script manual de verificação)

**Interfaces:**
- Consumes: `TrayService.showWindow()` e `navigatorKey` (Task 1), `BridgeServer`/`SecurePairingStore` (Task 4), `BrowserSaveCoordinator` (Task 5), `SessionProvider.isUnlocked`, `VaultProvider.createCredential`.

- [ ] **Step 1: Wiring no `main.dart`**

Dentro do bloco `if (isWindows)` da Task 1, após criar o `tray`:

```dart
final coordinator = BrowserSaveCoordinator(
  sessionListenable: session,
  isUnlocked: () => session.isUnlocked,
  createCredential: vault.createCredential,
  onNeedUnlock: tray.showWindow,
);
final bridge = BridgeServer(
  pairingStore: SecurePairingStore(),
  onPairRequest: (client) => _askPairing(client, tray),
  onSave: coordinator.handleSave,
);
// Sem porta livre o bridge fica desligado; o resto do app segue normal.
await bridge.start();
```

Imports novos em `main.dart`:

```dart
import 'services/browser_bridge/bridge_server.dart';
import 'services/browser_bridge/pairing_store.dart';
import 'state/browser_save_coordinator.dart';
```

E a função (top-level, no fim do arquivo):

```dart
Future<bool> _askPairing(String client, TrayService tray) async {
  await tray.showWindow();
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return false;
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: const Text('Conectar extensão do navegador?'),
      content: Text(
          '“$client” pede permissão para enviar logins capturados no navegador para o cofre. '
          'Nenhum dado do cofre sai por essa conexão.'),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(c, false), child: const Text('Negar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Permitir')),
      ],
    ),
  );
  return ok ?? false;
}
```

- [ ] **Step 2: Script de fumaça `tool/bridge_smoke.dart`**

Simula a extensão sem navegador (rodar com o app aberto):

```dart
// Uso: dart run tool/bridge_smoke.dart
// Faz o pareamento (aceite o diálogo no app) e salva uma credencial de teste.
import 'dart:convert';
import 'dart:io';

const ports = [19457, 19458, 19459];

Future<void> main() async {
  WebSocket? ws;
  for (final p in ports) {
    try {
      ws = await WebSocket.connect('ws://127.0.0.1:$p');
      stdout.writeln('conectado na porta $p');
      break;
    } catch (_) {}
  }
  if (ws == null) {
    stdout.writeln('keyring não encontrado — o app está aberto?');
    exit(1);
  }
  final replies = StreamIterator(ws);

  Future<Map<String, dynamic>> request(Map<String, dynamic> msg) async {
    ws!.add(jsonEncode(msg));
    await replies.moveNext();
    return jsonDecode(replies.current as String) as Map<String, dynamic>;
  }

  final pair = await request({'type': 'pair', 'client': 'bridge_smoke.dart'});
  stdout.writeln('pair: $pair');
  if (pair['ok'] != true) exit(1);

  final save = await request({
    'type': 'save',
    'token': pair['token'],
    'url': 'https://exemplo.teste/login',
    'username': 'usuario-fumaca',
    'password': 'senha-fumaca',
  });
  stdout.writeln('save: $save');
  await ws.close();
}
```

- [ ] **Step 3: Verificar manualmente**

Run: `flutter analyze` e `flutter test` — sem erros novos, suíte verde.
Run: `flutter run -d windows`, depois em outro terminal `dart run tool/bridge_smoke.dart`:
1. App traz a janela e mostra o diálogo de pareamento; Permitir → `pair: {ok: true, ...}`.
2. Com o cofre aberto: `save: {status: ok}` e a credencial "exemplo.teste" aparece na lista.
3. Bloquear o cofre (bandeja → Bloquear) e rodar o script de novo (sem parear — já tem token):
   janela volta pedindo desbloqueio; ao desbloquear, `status: ok`.
4. Deixar sem desbloquear ~2 min: `status: cancelled`.
5. Apagar a credencial de teste pelo app.

- [ ] **Step 4: Commit**

```powershell
git add lib/main.dart tool/bridge_smoke.dart
git commit -m "feat: bridge ativo no app com dialogo de pareamento"
```

---

## Fase C — Extensão Chrome/Edge

### Task 7: Estrutura da extensão + captura e banner (content script)

**Files:**
- Create: `browser-extension/manifest.json`
- Create: `browser-extension/content.js`
- Create: `browser-extension/icons/icon128.png` (cópia de `assets/icon_app.png`)

**Interfaces:**
- Produces (contrato de mensagens internas da extensão, consumido pela Task 8):
  - content → background: `{type:'captured', url, username, password}`, `{type:'get-pending'}` → resposta `{url, username}` ou `null`, `{type:'save'}` → resposta `{status}`, `{type:'dismiss'}` → `null`.

- [ ] **Step 1: `manifest.json` + ícone**

```powershell
New-Item -ItemType Directory -Force browser-extension/icons
Copy-Item assets/icon_app.png browser-extension/icons/icon128.png
```

`browser-extension/manifest.json`:

```json
{
  "manifest_version": 3,
  "name": "Keyring — salvar logins",
  "version": "0.1.0",
  "description": "Detecta logins em sites e oferece salvar no cofre Keyring.",
  "minimum_chrome_version": "116",
  "permissions": ["storage"],
  "background": { "service_worker": "background.js" },
  "content_scripts": [
    {
      "matches": ["http://*/*", "https://*/*"],
      "js": ["content.js"],
      "run_at": "document_idle"
    }
  ],
  "icons": { "128": "icons/icon128.png" }
}
```

- [ ] **Step 2: `content.js`**

```js
// Keyring — captura logins e mostra o banner "salvar?".
// A senha vai só para o background; o banner nunca a recebe de volta.

function captureFrom(form) {
  const pass = form.querySelector('input[type="password"]');
  if (!pass || !pass.value) return null;
  const user = [...form.querySelectorAll('input')].find(
    (i) => ['text', 'email', 'tel'].includes(i.type) && i.value
  );
  return {
    url: location.origin + location.pathname,
    username: user ? user.value : '',
    password: pass.value,
  };
}

document.addEventListener(
  'submit',
  (ev) => {
    if (!(ev.target instanceof HTMLFormElement)) return;
    const captured = captureFrom(ev.target);
    if (!captured) return;
    chrome.runtime.sendMessage({ type: 'captured', ...captured });
  },
  true
);

// Na carga da página, verifica se a navegação anterior desta aba deixou um
// login capturado pendente. Se o app não estiver aberto, o background
// responde null e nada aparece.
(async () => {
  let pending = null;
  try {
    pending = await chrome.runtime.sendMessage({ type: 'get-pending' });
  } catch (_) {
    return; // service worker indisponível
  }
  if (pending && pending.url) showBanner(pending);
})();

function showBanner(pending) {
  const host = document.createElement('div');
  host.id = 'keyring-save-banner';
  const shadow = host.attachShadow({ mode: 'closed' });
  shadow.innerHTML = `
    <style>
      .box {
        position: fixed; top: 16px; right: 16px; z-index: 2147483647;
        background: #101318; color: #e8e6e3; border: 1px solid #2a2f38;
        border-radius: 12px; padding: 14px 16px; width: 320px;
        font: 13px/1.45 system-ui, sans-serif;
        box-shadow: 0 8px 30px rgba(0,0,0,.45);
      }
      .title { font-weight: 600; margin-bottom: 2px; }
      .sub { color: #9aa0a8; margin-bottom: 10px; word-break: break-all; }
      .row { display: flex; gap: 8px; justify-content: flex-end; }
      button {
        border-radius: 8px; padding: 6px 14px; cursor: pointer; font: inherit;
      }
      .save { background: #c9a44a; border: none; color: #101318; font-weight: 600; }
      .no { background: transparent; border: 1px solid #2a2f38; color: #9aa0a8; }
    </style>
    <div class="box">
      <div class="title">Salvar este login no keyring?</div>
      <div class="sub"></div>
      <div class="row">
        <button class="no">Agora não</button>
        <button class="save">Salvar</button>
      </div>
    </div>`;
  const site = new URL(pending.url).hostname;
  const who = pending.username ? `${pending.username} em ${site}` : site;
  shadow.querySelector('.sub').textContent = who;

  const close = () => host.remove();
  shadow.querySelector('.no').addEventListener('click', async () => {
    await chrome.runtime.sendMessage({ type: 'dismiss' });
    close();
  });
  shadow.querySelector('.save').addEventListener('click', async () => {
    const title = shadow.querySelector('.title');
    const row = shadow.querySelector('.row');
    row.style.display = 'none';
    title.textContent = 'Salvando… desbloqueie o cofre se ele pedir.';
    const res = await chrome.runtime.sendMessage({ type: 'save' });
    const messages = {
      ok: 'Salvo no keyring ✓',
      cancelled: 'Cofre não foi desbloqueado — nada salvo.',
      busy: 'Outro salvamento em andamento. Tente de novo.',
      denied: 'Conexão negada no app keyring.',
      unreachable: 'O keyring não está aberto.',
      error: 'Não foi possível salvar.',
    };
    title.textContent = messages[res && res.status] || messages.error;
    setTimeout(close, 4000);
  });

  document.documentElement.appendChild(host);
  setTimeout(() => { if (host.isConnected) close(); }, 30000);
}
```

- [ ] **Step 3: Verificação estática**

O content script depende do background (Task 8) para responder mensagens, então o
teste funcional fica na Task 9. Aqui: carregar a extensão em `chrome://extensions`
(Modo do desenvolvedor → "Carregar sem compactação" → pasta `browser-extension/`)
e conferir que carrega sem erro de manifest/sintaxe.

- [ ] **Step 4: Commit**

```powershell
git add browser-extension/manifest.json browser-extension/content.js browser-extension/icons/icon128.png
git commit -m "feat: extensao - captura de login e banner de salvamento"
```

### Task 8: Cliente WebSocket da extensão (background.js)

**Files:**
- Create: `browser-extension/background.js`
- Create: `browser-extension/README.md`

**Interfaces:**
- Consumes: mensagens internas da Task 7; protocolo WebSocket da Task 3 (`pair`/`pair-result`, `save`/`save-result`); portas `19457–19459`.

- [ ] **Step 1: `background.js`**

```js
// Keyring — service worker: guarda capturas por aba e fala com o app via
// WebSocket local. Token de pareamento fica em chrome.storage.local.

const PORTS = [19457, 19458, 19459];
const PENDING_TTL_MS = 60000;

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  handle(msg, sender).then(sendResponse);
  return true; // resposta assíncrona
});

async function handle(msg, sender) {
  const tabId = sender.tab && sender.tab.id;
  if (tabId == null) return null;
  const key = `pending_${tabId}`;
  switch (msg.type) {
    case 'captured':
      await chrome.storage.session.set({
        [key]: { url: msg.url, username: msg.username, password: msg.password, at: Date.now() },
      });
      return null;

    case 'get-pending': {
      const { [key]: pending } = await chrome.storage.session.get(key);
      if (!pending || Date.now() - pending.at > PENDING_TTL_MS) {
        await chrome.storage.session.remove(key);
        return null;
      }
      if (!(await appReachable())) return null; // app fechado: silêncio
      return { url: pending.url, username: pending.username }; // sem a senha
    }

    case 'save': {
      const { [key]: pending } = await chrome.storage.session.get(key);
      if (!pending) return { status: 'error' };
      const status = await saveInKeyring(pending, false);
      if (status !== 'busy') await chrome.storage.session.remove(key);
      return { status };
    }

    case 'dismiss':
      await chrome.storage.session.remove(key);
      return null;
  }
  return null;
}

function openSocket(port) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    ws.onopen = () => resolve(ws);
    ws.onerror = () => reject(new Error('sem conexão'));
  });
}

async function connect() {
  for (const port of PORTS) {
    try {
      return await openSocket(port);
    } catch (_) { /* tenta a próxima */ }
  }
  return null;
}

async function appReachable() {
  const ws = await connect();
  if (!ws) return false;
  ws.close();
  return true;
}

function request(ws, payload, timeoutMs) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timeout')), timeoutMs);
    ws.onmessage = (ev) => { clearTimeout(timer); resolve(JSON.parse(ev.data)); };
    ws.onclose = () => { clearTimeout(timer); reject(new Error('conexão fechada')); };
    ws.send(JSON.stringify(payload));
  });
}

async function ensureToken(ws) {
  const { token } = await chrome.storage.local.get('token');
  if (token) return token;
  // Primeira vez: o app traz a janela e pergunta ao usuário (até 2 min).
  const res = await request(ws, { type: 'pair', client: 'Extensão Keyring (Chrome/Edge)' }, 120000);
  if (!res.ok || !res.token) return null;
  await chrome.storage.local.set({ token: res.token });
  return res.token;
}

async function saveInKeyring(pending, isRetry) {
  const ws = await connect();
  if (!ws) return 'unreachable';
  try {
    const token = await ensureToken(ws);
    if (!token) return 'denied';
    const res = await request(
      ws,
      { type: 'save', token, url: pending.url, username: pending.username, password: pending.password },
      180000 // espera o desbloqueio do cofre (timeout do app: 2 min)
    );
    if (res.status === 'invalid-token' && !isRetry) {
      // Token revogado/perdido no app: re-pareia uma única vez.
      await chrome.storage.local.remove('token');
      ws.close();
      return saveInKeyring(pending, true);
    }
    return res.status;
  } catch (_) {
    return 'error';
  } finally {
    try { ws.close(); } catch (_) {}
  }
}
```

- [ ] **Step 2: `browser-extension/README.md`**

```markdown
# Extensão Keyring (Chrome/Edge)

Detecta envios de formulário de login e oferece salvar usuário e senha no app
Keyring, via WebSocket local (127.0.0.1, portas 19457–19459).

## Instalar (modo desenvolvedor)

1. Abra `chrome://extensions` (ou `edge://extensions`).
2. Ative "Modo do desenvolvedor".
3. "Carregar sem compactação" → selecione esta pasta `browser-extension/`.

Requer Chrome/Edge 116+ e o app Keyring aberto (pode estar na bandeja).

## Como funciona

- Ao enviar um formulário com senha, a captura fica pendente por até 60 s
  (memória da sessão do navegador, por aba).
- Na página seguinte, um banner pergunta "Salvar este login no keyring?".
- Na primeira vez, o app pede permissão para parear; o token fica em
  `chrome.storage.local`.
- A conexão é só de escrita: o app nunca envia segredos do cofre à extensão.
```

- [ ] **Step 3: Verificação estática**

Recarregar a extensão em `chrome://extensions` e conferir: sem erros no service
worker (link "service worker" → console limpo ao recarregar uma página qualquer).

- [ ] **Step 4: Commit**

```powershell
git add browser-extension/background.js browser-extension/README.md
git commit -m "feat: extensao - cliente WebSocket com pareamento e salvamento"
```

### Task 9: Teste ponta a ponta e ajustes finais

**Files:**
- Modify: o que os ajustes exigirem (registrar cada um no commit).

- [ ] **Step 1: Roteiro manual completo**

Com `flutter run -d windows` (ou o exe de release) aberto e a extensão carregada:

1. Ir a um site de teste de login (ex.: `https://the-internet.herokuapp.com/login`,
   usuário `tomsmith`, senha `SuperSecretPassword!`) e enviar o formulário.
2. Na página seguinte: banner "Salvar este login no keyring?" com "tomsmith em the-internet.herokuapp.com".
3. Clicar Salvar pela primeira vez → app traz a janela com o diálogo de pareamento → Permitir.
4. Banner confirma "Salvo no keyring ✓"; credencial "the-internet.herokuapp.com" na lista com URL, usuário e senha.
5. Bloquear o cofre (bandeja → Bloquear cofre), repetir o login no site → Salvar →
   janela do app volta pedindo desbloqueio → desbloquear → "Salvo no keyring ✓".
6. Fechar o app de verdade (bandeja → Sair), repetir o login → nenhum banner aparece.
7. Reabrir o app, clicar "Agora não" num banner → nada é salvo e o banner some.
8. Formulário sem senha (ex.: busca) → nenhuma captura/banner.

- [ ] **Step 2: Suíte e análise**

Run: `flutter test` e `flutter analyze` — tudo verde.

- [ ] **Step 3: Commit de ajustes (se houver)**

```powershell
git add <arquivos ajustados>
git commit -m "fix: ajustes do teste ponta a ponta da extensao"
```
