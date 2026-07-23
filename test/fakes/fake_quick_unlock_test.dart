import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyring/services/quick_unlock.dart';
import 'fake_quick_unlock.dart';

void main() {
  test('devolve a chave gravada', () async {
    final f = FakeQuickUnlockService();
    expect(await f.saveKey(Uint8List.fromList([1, 2, 3]), reason: 'x'), QuickKeyStatus.ok);
    final r = await f.readKey(reason: 'x');
    expect(r.status, QuickKeyStatus.ok);
    expect(r.key, Uint8List.fromList([1, 2, 3]));
  });

  test('sem chave gravada devolve missing', () async {
    final r = await FakeQuickUnlockService().readKey(reason: 'x');
    expect(r.status, QuickKeyStatus.missing);
    expect(r.key, isNull);
  });

  test('guarda uma copia: zerar o buffer do chamador nao apaga a chave', () async {
    final f = FakeQuickUnlockService();
    final k = Uint8List.fromList([7, 7, 7]);
    await f.saveKey(k, reason: 'x');
    k.fillRange(0, k.length, 0);
    expect((await f.readKey(reason: 'x')).key, Uint8List.fromList([7, 7, 7]));
  });

  test('clearKey apaga e conta as chamadas', () async {
    final f = FakeQuickUnlockService();
    await f.saveKey(Uint8List.fromList([1]), reason: 'x');
    await f.clearKey();
    expect(f.clearCalls, 1);
    expect((await f.readKey(reason: 'x')).status, QuickKeyStatus.missing);
  });
}
