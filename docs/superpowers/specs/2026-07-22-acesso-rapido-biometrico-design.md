# Acesso rápido por biometria

Data: 2026-07-22
Status: aprovado, pronto para planejamento

## Problema

Abrir o cofre exige senha mestra **e** código TOTP do Authy em toda abertura, inclusive
depois do auto-lock de 5 minutos de inatividade. Pegar o celular e copiar 6 dígitos várias
vezes por dia é o gargalo — a senha mestra, sozinha, não incomoda.

## Contexto de segurança

Hoje, em `SessionProvider.unlock`, o TOTP é verificado **depois** de a senha mestra derivar
a KEK (Argon2id) e desembrulhar o DEK. O segredo TOTP está cifrado com o próprio DEK, então
só é possível conferi-lo com o cofre já aberto. Consequências:

- O TOTP é uma checagem lógica no app, não uma barreira criptográfica.
- Quem tiver o `vault.db` e a senha mestra lê tudo sem o Authy.
- Portanto, remover o TOTP do caminho de acesso rápido **não** enfraquece a criptografia.

A proteção real do cofre é a senha mestra + Argon2id. É essa que o acesso rápido substitui,
e é por isso que a substituta precisa estar presa ao dispositivo.

## Decisões

| Questão | Decisão |
|---|---|
| Plataformas-alvo | Android (APK) e Windows desktop |
| Fator de acesso rápido | Biometria do SO — digital no Android, Windows Hello no Windows |
| Login completo obrigatório | A cada 7 dias, contados do último login completo |
| Auto-lock por inatividade | Continua em 5 minutos (agora custa um toque) |
| Onde mora a chave | Metade no keystore do SO, metade no `vault.db` |
| Proteção da chave no Android | Presa ao hardware — `AndroidOptions.biometric` |
| minSdk | Sobe de 24 para **28** (exigido pela chave biométrica) |
| Fallback quando a digital falha | Aceita o PIN/padrão do aparelho (`biometricOrDeviceCredential`) |
| Aparelho sem tela de bloqueio | Acesso rápido recusado (`enforceBiometrics: true`) |

## Arquitetura

Chave de acesso rápido **indireta**: uma `quickKey` aleatória de 32 bytes envolve o DEK, e
as duas metades ficam separadas.

```
quickKey (32 bytes) ──► keystore do SO   (Android Keystore / DPAPI no Windows)
wrapped_dek_quick   ──► tabela vault_meta (vault.db)

DEK = unwrapDek(wrapped_dek_quick, quickKey)
```

Nenhuma metade serve sozinha. O `vault.db` — que vai para backup, pendrive, sync — não
contém nada utilizável em outro aparelho. O keystore sem o banco também não. Revogar o
acesso rápido é um `UPDATE` de uma linha, e funciona mesmo se o keystore estiver
inacessível.

> **Pré-requisito, já satisfeito na 1.0.2.** Essa separação depende de as duas metades não
> saírem juntas do aparelho. Até a 1.0.1, o `allowBackup` implícito mandava todo o diretório
> de dados do app para o Google Drive — o que teria incluído **tanto** o `vault.db` **quanto**
> o EncryptedSharedPreferences onde o `flutter_secure_storage` guarda a `quickKey`. As duas
> metades, no mesmo backup, na mesma conta. A correção da 1.0.2 (`allowBackup="false"` +
> `data_extraction_rules.xml`) é o que torna este design válido; se ela for revertida, o
> acesso rápido passa a ser um passivo em vez de uma conveniência.

A alternativa avaliada e recusada foi guardar o DEK direto no keystore: economiza a
migração de schema, mas expõe o DEK cru ao storage do SO e perde a separação
banco/dispositivo.

### Escolha do backend: forte no Android, lógico no Windows

Implementação em Dart puro com `flutter_secure_storage` ^10.3.1 e `local_auth` ^3.0.2. As
duas plataformas alcançam níveis de proteção diferentes, e a diferença é material.

**Android — chave presa ao hardware.** O `AndroidOptions.biometric` faz o backend nativo do
pacote gerar a chave dentro do Keystore com:

```java
builder.setUserAuthenticationRequired(true);
builder.setUserAuthenticationParameters(0, authTypes);  // timeout 0 = autentica a cada uso
builder.setInvalidatedByBiometricEnrollment(true);
builder.setUnlockedDeviceRequired(true);                 // API 28+
builder.setIsStrongBoxBacked(true);                      // quando o aparelho tem StrongBox
```

(verificado em `KeyCipherImplementationAES23.java:140-185` do pacote, não na documentação)

A `quickKey` nunca sai do TEE, cada leitura exige autenticação, e cadastrar uma digital nova
no aparelho **destrói** a chave. Root não é suficiente. É a proteção que eu havia atribuído
a um plugin nativo de semanas de trabalho; custa uma linha de configuração.

Consequência de arquitetura: no Android o próprio storage dispara o `BiometricPrompt` ao ler
a chave. O `local_auth` fica sendo usado **apenas no Windows**.

**Windows — ligação lógica.** `WindowsOptions` expõe só `useBackwardCompatibility`; o
armazenamento é DPAPI, protegido pela conta do Windows, com o `local_auth` (Hello) por cima.
A ligação entre a autenticação e a chave é decidida pelo app, não imposta pelo SO. Malware
rodando como o mesmo usuário consegue extrair a `quickKey`. É o modelo que Bitwarden e
1Password usam no desktop, e não há alternativa em Dart puro.

Essa assimetria é aceitável porque acompanha o risco: o celular é o que se perde e é
roubado; o desktop fica numa sala.

## Componentes

### `QuickUnlockService` (novo — `lib/services/quick_unlock.dart`)

Interface abstrata + implementação real, seguindo o padrão de
`lib/state/vault_repository_factory.dart`. É a única fronteira que os testes falsificam, e
o único lugar do app que conhece `local_auth` e `flutter_secure_storage`.

```dart
enum QuickKeyStatus { ok, cancelled, unavailable, missing }

class QuickKeyResult {
  final QuickKeyStatus status;
  final Uint8List? key;   // preenchido apenas quando status == ok
}

abstract class QuickUnlockService {
  Future<bool> isAvailable();
  Future<QuickKeyStatus> saveKey(Uint8List quickKey, {required String reason});
  Future<QuickKeyResult> readKey({required String reason});
  Future<void> clearKey();
}
```

O prompt de autenticação **não** é um método separado da interface, porque as duas
plataformas o disparam em momentos diferentes: no Android o próprio Keystore o exige ao
usar a chave (`setUserAuthenticationParameters(0, ...)`), enquanto no Windows o app precisa
chamar o `local_auth` antes de tocar no DPAPI. Cada implementação resolve isso por dentro;
quem chama só pede a chave e recebe um desfecho.

`QuickKeyStatus` distingue o que a UI trata de formas diferentes — `cancelled` (usuário
desistiu, não invalida nada) de `missing` (chave ausente ou destruída pelo SO, invalida).

### Schema v2 — `lib/services/database.dart`

Duas colunas nullable em `vault_meta`, adicionadas via `ALTER TABLE` no `_migrate` já
preparado. `kVaultSchemaVersion` passa de 1 para 2.

| coluna | tipo | conteúdo |
|---|---|---|
| `wrapped_dek_quick` | BLOB | DEK envolvido pela `quickKey`, via o `wrapDek` existente |
| `quick_expires_at` | TEXT | ISO-8601 — vencimento da janela de 7 dias |

Ambas nulas significa acesso rápido desligado. `VaultMetaRow` ganha os dois campos como
nullable; `createSchema` passa a criá-las já na v2 para bancos novos.

Método novo no repositório:

```
Future<void> updateQuickUnlock(Uint8List? wrapped, String? expiresAt)
```

Escreve só essas duas colunas, sem reescrever a meta inteira.

### `SessionProvider`

```
bool get quickUnlockEnabled          // há blob no banco
Future<bool> quickUnlockAvailable()  // plataforma suporta
DateTime? get quickUnlockExpiresAt

Future<bool> enableQuickUnlock()     // exige cofre aberto
Future<void> disableQuickUnlock()
Future<QuickUnlockOutcome> unlockWithBiometrics()
```

`enableQuickUnlock` retorna `false` quando o prompt de confirmação é cancelado ou a
plataforma não suporta — em ambos os casos nada é gravado e o toggle volta para desligado.

`QuickUnlockOutcome` distingue os desfechos que a UI trata de formas diferentes:
`success`, `cancelled`, `unavailable`, `expired`, `invalidated`.

## Fluxos

### Ativar (nas configurações, com o cofre aberto)

1. `isAvailable()` — sem tela de bloqueio configurada, para aqui com mensagem explicativa.
2. Gera `quickKey` com o `Random.secure()` já existente em `CryptoService`.
3. `wrapDek(dek, quickKey)`.
4. `saveKey(quickKey)` — **dispara o prompt do SO**. No Android porque o Keystore exige
   autenticação para usar a chave recém-criada; no Windows porque a implementação chama o
   `local_auth` antes de gravar. Se voltar `cancelled`, nada foi gravado e o toggle volta
   para desligado.
5. Grava blob e `agora + 7 dias` via `updateQuickUnlock`.
6. Zera a `quickKey` da memória.

O prompt no passo 4 é também a confirmação de que a biometria funciona — não faz sentido
confiar num sensor que ainda não testamos.

A ordem dos passos 4 e 5 importa. Keystore primeiro: se a escrita no banco falhar, sobra uma
chave órfã no keystore — inofensiva, e sobrescrita na próxima tentativa. Na ordem inversa,
sobraria um blob no banco sem chave correspondente, e a próxima abertura cairia em
`invalidated` sem que o usuário tenha feito nada.

### Entrar com biometria

1. App abre; há blob e a data não venceu.
2. `readKey()` — dispara o prompt do SO automaticamente, **uma vez**.
3. `unwrapDek(blob, quickKey)`.
4. DEK em memória, cofre aberto, timer de auto-lock iniciado, `quickKey` zerada.

Sem senha, sem Authy.

### Login completo

Idêntico a hoje. Ao final, se o acesso rápido estiver ativo, **renova**
`quick_expires_at` para +7 dias.

A janela conta do último login completo e **nunca** é estendida por usar a digital — é isso
que implementa a regra dos 7 dias.

## Invalidação

A distinção mais fácil de errar: falha acidental não pode custar reconfiguração, e estado
ambíguo não pode virar acesso silencioso.

**Invalida** — zera as duas colunas e chama `clearKey()`:

- O usuário desativa nas configurações.
- `readKey()` devolve `missing`: app reinstalado, keystore resetado, `vault.db` trazido de
  outro aparelho, ou — no Android — **uma digital nova foi cadastrada no aparelho**, e o
  Keystore destruiu a chave por conta própria.
- `unwrapDek` falha na tag GCM: chave trocada ou blob corrompido.

Os dois últimos são o mesmo caso — a metade do dispositivo não bate com a metade do banco.
Cai para o login completo com aviso claro, sem exceção propagando para a UI.

O caso da digital nova é o único em que o SO invalida sozinho, sem o app pedir. Não é erro:
é a proteção funcionando. A mensagem ao usuário reflete isso, em vez de sugerir defeito.

**Não invalida** — apenas volta ao formulário completo:

- Prompt cancelado pelo usuário.
- Biometria não reconhecida, ou lockout do SO por excesso de tentativas (o SO já limita;
  o app não reimplementa contador).
- Janela de 7 dias vencida — o blob continua criptograficamente válido e o login completo
  simplesmente renova a data.

### Limitações conhecidas

**O PIN do aparelho abre o cofre — nas duas plataformas.** No Windows isso é imposto: o
Hello aceita o PIN e o `local_auth` não permite recusá-lo. No Android é uma escolha
deliberada (`biometricOrDeviceCredential`), trocando segurança por não ficar preso fora do
cofre quando o sensor não lê o dedo. O efeito: quem souber o PIN do seu celular, ou o do seu
Windows, entra sem a senha mestra.

Os dois PINs são presos ao hardware (TEE no Android, TPM no Windows), então não são
segredos copiáveis que vazam de um aparelho para outro. Mas são curtos e digitados em
público. **Se isso incomodar, `AndroidBiometricType.strongBiometricOnly` fecha o lado
Android** — uma linha, e a digital passa a ser o único caminho rápido lá.

Por isso a UI não usa a palavra "digital" em lugar nenhum: os rótulos são "Entrar com
digital ou PIN" no Android e "Entrar com Windows Hello" no Windows.

**Windows não tem chave presa ao hardware.** Detalhado em *Escolha do backend*: lá a
proteção é lógica, e malware rodando como seu usuário consegue extrair a `quickKey`. No
Android, não.

**Fora de escopo:** troca de senha mestra não existe no app hoje. Quando existir, decidir se
invalida o acesso rápido — tecnicamente não precisa (o DEK não muda), mas quem troca a senha
mestra normalmente suspeita de comprometimento.

### Risco pré-existente que este design amplifica: recovery codes não recuperam nada

Os 8 códigos gerados no setup são exibidos ao usuário e têm o SHA-256 gravado em
`recovery_codes_hash`, mas **nenhum código no app lê essa coluna** — não existe fluxo de
recuperação. E não é questão de faltar uma tela: o DEK só está envolvido pela KEK da senha
mestra (`wrapped_dek`). Não existe uma segunda cópia envolvida por chave derivada dos
códigos, e um hash não reconstrói chave alguma. Esquecer a senha mestra hoje significa perder
o cofre — os códigos guardados não mudam isso.

O acesso rápido não cria esse problema, mas mexe nos dois lados dele: reduz a repetição que
mantinha a senha mestra na memória muscular (de várias vezes ao dia para uma vez por semana)
e, ao mesmo tempo, abre a única saída viável — uma sessão aberta por biometria tem o DEK em
mãos e poderia re-envolvê-lo com uma senha nova.

Fora do escopo desta spec. Registrado aqui porque a decisão de tratá-lo, e como, deve ser
tomada com o acesso rápido em vista.

## Interface

### `UnlockScreen` — dois modos

**Modo rápido** (padrão quando disponível): mantém logo e título; no lugar dos dois campos,
um botão grande com ícone de digital — *"Entrar com digital ou PIN"* no Android, *"Entrar
com Windows Hello"* no Windows — e abaixo um link discreto *"Usar senha mestra"* que revela
o formulário atual.

Os rótulos evitam a palavra "digital" sozinha de propósito: nas duas plataformas o PIN do
aparelho também abre o cofre, e prometer só biometria seria mentir sobre o que protege o
cofre.

O prompt do SO dispara sozinho ao abrir a tela, uma vez. Cancelou, o botão fica disponível
para nova tentativa — sem reabrir em loop.

**Modo completo:** o formulário de hoje, inalterado. É o fallback de todos os desfechos que
não são `success`, cada um com sua mensagem:

| desfecho | mensagem |
|---|---|
| `expired` | "Já se passaram 7 dias — confirme sua senha mestra." |
| `invalidated` | "Acesso rápido foi desativado neste dispositivo. Entre com a senha mestra para reativá-lo." |
| `cancelled` | sem mensagem — o botão continua ali |

### `SettingsScreen`

Toggle "Acesso rápido", com subtítulo refletindo o estado real. O texto do estado desligado
muda por plataforma, pela mesma razão do rótulo da `UnlockScreen` — no Windows o fator pode
ser o PIN do Hello, e chamá-lo de digital seria enganoso:

- desligado, Android → "Use sua digital ou o PIN do aparelho para abrir o cofre sem a senha mestra"
- desligado, Windows → "Use o Windows Hello para abrir o cofre sem a senha mestra"
- ligado → "Ativo. Senha mestra será pedida em 29/07" (data real de `quick_expires_at`)
- plataforma sem suporte → o item não aparece
- Android sem tela de bloqueio → item visível mas desabilitado, com "Configure uma digital ou
  PIN no aparelho para usar o acesso rápido" — aqui explicar é melhor que esconder, porque o
  usuário consegue resolver

## Testes

Com `FakeQuickUnlockService` em memória, sem tocar em hardware. Estende
`test/session_provider_test.dart` e `test/migration_test.dart`.

1. Ativar → travar → entrar com biometria devolve **o mesmo DEK**.
2. Biometria negada (`cancelled`) → `isUnlocked` continua falso, DEK não vaza e o acesso
   rápido **continua ativo** (falha acidental não custa reconfiguração).
3. Chave ausente (`missing`) → colunas zeradas, desfecho `invalidated`, sem exceção.
4. Blob corrompido → mesmo tratamento do caso 3.
5. Janela vencida (data gravada no passado direto no banco) → desfecho `expired`, exige
   login completo, e o blob **não** é apagado.
6. Login completo com acesso rápido ativo → renova para +7 dias.
7. Desativar → colunas nulas e `clearKey()` chamado.
8. Ativar com `saveKey` devolvendo `cancelled` → nada gravado no banco, acesso rápido segue
   desligado (cobre a ordem keystore-antes-do-banco).
9. Ativar com `isAvailable() == false` → recusa sem gravar nada.
10. Migração v1→v2 preserva credenciais existentes.

O teste 5 grava `quick_expires_at` diretamente no banco em vez de injetar um relógio — evita
adicionar injeção de tempo ao código de produção só para teste.

## Riscos de implementação

**minSdk 24 → 28.** `AndroidOptions.biometric` requer API 28 (o `setUnlockedDeviceRequired`
e o StrongBox são 28+). O projeto herda `flutter.minSdkVersion` = 24
(`FlutterExtension.kt:26`), então `android/app/build.gradle.kts` passa a fixar `minSdk = 28`
explicitamente em vez de herdar. Aparelhos com Android 8 ou anterior deixam de instalar o
app — decisão tomada com isso em vista.

**Chave invalidada pelo SO é um caminho normal, não um erro.** Com
`setInvalidatedByBiometricEnrollment(true)`, cadastrar uma digital nova destrói a chave e a
leitura seguinte falha. O `flutter_secure_storage` usa `resetOnError: true` por padrão, que
limpa o storage nesse caso — comportamento desejado aqui, já que só guardamos a `quickKey`.
A implementação deve traduzir isso para `QuickKeyStatus.missing`, e o app para o desfecho
`invalidated`, sem exceção chegando à UI.

**`local_auth` no Windows.** O suporte vem do pacote federado `local_auth_windows`
(`UserConsentVerifier`). Confirmar que está incluído por padrão na versão escolhida de
`local_auth` e que a flag `biometricOnly` é ignorada na plataforma — o comportamento
esperado está descrito em Limitações conhecidas.

**`flutter_secure_storage` no Android.** Definir `AndroidOptions` com
`encryptedSharedPreferences: true` explicitamente, sem depender do padrão da versão.
