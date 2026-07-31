/// Contextos que amarram cada blob cifrado ao lugar exato onde ele vive.
///
/// Vão como AAD no AES-GCM: fazem parte do cálculo da tag sem serem cifrados,
/// então mover um blob para outra linha ou outra coluna do SQLite passa a
/// falhar na autenticação em vez de decifrar no lugar errado.
///
/// As strings são formato persistido — mudá-las torna ilegíveis os blobs já
/// gravados. Para alterar a convenção é preciso subir a versão do formato de
/// cifra e re-cifrar, como foi feito na migração v1→v2.
class CipherContext {
  const CipherContext._();

  static String credential(String id, String field) => 'credential:$id:$field';
  static String server(String id, String field) => 'server:$id:$field';
  static String command(String id, String field) => 'command:$id:$field';
  static String tag(String id) => 'tag:$id:name';

  /// Segredo TOTP na linha única de `vault_meta`.
  static const String totp = 'meta:totp';
}
