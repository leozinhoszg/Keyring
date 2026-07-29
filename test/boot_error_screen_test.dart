import 'package:flutter_test/flutter_test.dart';
import 'package:keyring/screens/boot_error_screen.dart';

void main() {
  testWidgets('falha de inicialização mostra o erro em vez de sumir', (tester) async {
    await tester.pumpWidget(const BootErrorApp(
      error: 'SqliteException(1): duplicate column name: wrapped_dek_quick',
      stack: '#0 migrateVault (vault_repository.dart:201)',
    ));

    // O usuário precisa saber que o app falhou, ver a causa e saber que os
    // dados estão preservados — era exatamente o que faltava no bug da migração.
    expect(find.text('O Keyring não conseguiu abrir'), findsOneWidget);
    expect(find.textContaining('duplicate column name'), findsOneWidget);
    expect(find.textContaining('Seus dados não foram alterados'), findsOneWidget);
  });
}
