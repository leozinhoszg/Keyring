<div align="center">

<img src="assets/icon_app.png" width="112" alt="Keyring" />

# Keyring

**Gerenciador de senhas local, offline e criptografado — para Windows e Android.**

</div>

Keyring é um cofre de senhas que roda **100% no seu dispositivo**: sem servidor, sem nuvem,
sem telemetria. Os segredos são protegidos com **Argon2id** (derivação de chave) e
**AES-256-GCM** (criptografia), e o acesso exige **senha mestra + TOTP** (Authy/Google Authenticator).

## ✨ Recursos

- 🔐 **Login com senha mestra + TOTP** (QR code para o Authy) e códigos de recuperação
- 🗝️ **Credenciais cifradas** — copiar usuário/senha, máscara, revelar sob demanda
- 🖥️ **Inventário de servidores** com trechos de comandos SSH copiáveis
- 🏷️ Tags/categorias, favoritos, busca instantânea
- 🎲 Gerador de senhas seguras, medidor de força e detecção de duplicatas
- 💾 **Backup criptografado** (export/import `.vault`) — sua ponte segura entre dispositivos
- 🔒 **Auto-lock** por inatividade e ao ir para segundo plano; limpeza automática do clipboard
- 🛡️ **Criptografia total em repouso**: nem títulos, IPs ou comandos ficam legíveis no banco

## 🔏 Segurança

- **Argon2id** para derivar a chave a partir da senha mestra; **AES-256-GCM** para os dados.
- A chave de dados (DEK) só existe em memória **enquanto o cofre está desbloqueado**.
- Descriptografia **sob demanda** — senhas nunca ficam retidas em memória.
- Todos os campos textuais (título, usuário, senha, notas, projeto, tags, servidores, comandos)
  são cifrados no banco. Perder a senha mestra torna os dados irrecuperáveis por design — use os backups.

## 🎨 Identidade

Design **"Steel & Gold"**: aço escovado escuro com detalhes em ouro, metáfora de um cofre premium.

## 🚀 Rodando o projeto

Requer **Flutter 3.41+**.

```bash
flutter pub get
flutter run -d windows   # desktop
flutter run              # dispositivo Android conectado
```

## 📦 Build

```bash
flutter build windows --release   # gera build/windows/x64/runner/Release/keyring.exe
flutter build apk --release       # gera o APK Android
```

## 🧱 Arquitetura

`lib/` segue camadas leves: `models/` (dados), `services/` (cripto, TOTP, banco, gerador),
`state/` (repository + providers com `provider`), `screens/`, `widgets/`, `theme/`.
Persistência via **SQLite** (`sqflite` no Android, `sqflite_common_ffi` no Windows).

## 📄 Licença

© 2026 Leonardo de Souza Guimarães.
