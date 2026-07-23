# Publicando uma versão do Keyring

## Por que o APK precisa de uma chave própria

Até a 1.0.1, o APK de release era assinado com a **chave de debug** do Android. O Gradle
gera essa chave automaticamente quando ela não existe — e o runner do GitHub Actions começa
limpo a cada execução. Na prática, cada build produzia um APK com identidade diferente.

Duas consequências:

- **Atualizar por cima falha.** O Android recusa instalar uma versão nova assinada por outra
  chave. A saída aparente é desinstalar — e desinstalar **apaga o `vault.db`**.
- **Não há como provar a origem.** Qualquer pessoa consegue produzir um APK assinado com uma
  chave de debug; nada distingue o seu do de outra pessoa.

Com uma chave estável, atualizações passam a instalar por cima normalmente e o cofre
permanece intacto entre versões.

## Passo 1 — Gerar a chave (uma única vez)

```bash
keytool -genkeypair -v \
  -keystore keyring-release.jks \
  -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -alias keyring
```

Guarde o arquivo `.jks` e a senha **fora do repositório** e com backup — um gerenciador de
senhas, um cofre físico, o que preferir.

> **Perder essa chave é definitivo.** Sem ela não existe mais como atualizar o app instalado:
> só desinstalando, o que apaga o cofre de quem tiver o app. Não há recuperação possível —
> nem por você, nem pelo Google.

## Passo 2 — Build local (opcional)

Crie `android/key.properties` — o `.gitignore` já o exclui:

```properties
storeFile=C:/Users/voce/chaves/keyring-release.jks
storePassword=sua-senha-do-keystore
keyAlias=keyring
keyPassword=sua-senha-da-chave
```

Use barras normais (`/`) mesmo no Windows: o formato `.properties` trata `\` como escape.

Sem esse arquivo, `flutter build apk --release` continua funcionando na sua máquina, mas cai
na chave de debug e emite um aviso. Serve para testar; não distribua o resultado.

## Passo 3 — Configurar o CI

Converta a chave para base64:

```powershell
# Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("keyring-release.jks")) | Set-Clipboard
```

```bash
# Linux/macOS
base64 -w0 keyring-release.jks | tee /dev/tty | clip
```

Em **Settings → Secrets and variables → Actions**, crie os quatro secrets:

| Secret | Conteúdo |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | o base64 gerado acima |
| `ANDROID_KEYSTORE_PASSWORD` | senha do keystore |
| `ANDROID_KEY_ALIAS` | `keyring` |
| `ANDROID_KEY_PASSWORD` | senha da chave |

Enquanto os secrets não existirem, o workflow **falha de propósito**, com a mensagem
apontando para este documento. É intencional: um APK publicado com chave de debug causa mais
estrago do que um build que não passa.

O workflow imprime o SHA-256 do certificado ao final. Vale conferir que ele não muda entre
releases — se mudou, a chave mudou, e as atualizações vão quebrar.

## A migração, uma vez só

O APK que já está instalado no seu celular foi assinado com uma chave de debug. O primeiro
APK assinado com a chave nova **não instala por cima dele**. É inevitável — nenhuma das duas
chaves consegue substituir a outra.

Na ordem:

1. No app atual, **Configurações → Exportar backup** e guarde o `.vault`.
2. Desinstale o Keyring.
3. Instale o APK novo.
4. Faça o setup: nova senha mestra e novo QR no Authy.
5. **Importar backup** com o `.vault` do passo 1.

Credenciais, servidores, comandos e tags voltam. Senha mestra e segredo TOTP não — o backup
não os carrega, por design. Os códigos de recuperação também são novos.

Da próxima atualização em diante, nada disso é necessário: o APK instala por cima e o cofre
fica onde está.
