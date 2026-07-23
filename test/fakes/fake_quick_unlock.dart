import 'dart:typed_data';
import 'package:keyring/services/quick_unlock.dart';

/// Fake em memória do keystore do SO, para os testes rodarem sem hardware.
///
/// Os campos públicos permitem encenar cada desfecho: `available`,
/// `nextSaveStatus` e `nextReadStatus`. Quando `nextReadStatus` é null, o
/// comportamento é o real — devolve a chave guardada, ou `missing` se não há.
class FakeQuickUnlockService implements QuickUnlockService {
  Uint8List? stored;
  bool available = true;
  QuickKeyStatus? nextSaveStatus;
  QuickKeyStatus? nextReadStatus;

  int clearCalls = 0;
  int readCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<QuickKeyStatus> saveKey(Uint8List quickKey, {required String reason}) async {
    final forced = nextSaveStatus;
    if (forced != null && forced != QuickKeyStatus.ok) return forced;
    // copia: o chamador zera o buffer original depois de gravar
    stored = Uint8List.fromList(quickKey);
    return QuickKeyStatus.ok;
  }

  @override
  Future<QuickKeyResult> readKey({required String reason}) async {
    readCalls++;
    final forced = nextReadStatus;
    if (forced != null && forced != QuickKeyStatus.ok) return QuickKeyResult(forced);
    final s = stored;
    if (s == null) return const QuickKeyResult(QuickKeyStatus.missing);
    return QuickKeyResult(QuickKeyStatus.ok, Uint8List.fromList(s));
  }

  @override
  Future<void> clearKey() async {
    clearCalls++;
    stored = null;
  }
}
