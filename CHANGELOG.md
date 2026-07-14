# Changelog

Todas as mudanças notáveis do **Keyring** são documentadas aqui.
O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/) e o versionamento é [SemVer](https://semver.org/lang/pt-BR/).

## [1.0.1] — 2026-07-14

### Corrigido
- **Primeiro cadastro:** o botão **"Confirmar e entrar"** não desbloqueava ao clicar — apenas
  a tecla **Enter** funcionava. Causa: o estado de "ocupado" não era limpo após criar o cofre,
  deixando o botão desabilitado na etapa do código TOTP.
- **Importar backup:** leitura do arquivo `.vault` agora é feita pelo caminho do arquivo (mais
  robusta no Windows) e as mensagens de erro são específicas — distinguem **senha do backup
  incorreta** de **arquivo inválido/corrompido**, em vez de sempre culpar a senha.

### Alterado
- **Exportar backup:** o arquivo agora recebe um nome com **data e hora legíveis**
  (`keyring-backup-AAAA-MM-DD_HH-MM-SS.vault`) e **nunca sobrescreve** um backup existente.

### Segurança & robustez
- **Migração de schema segura:** atualizações futuras **preservam o banco** do usuário. As migrações
  apenas adicionam/alteram estruturas (nunca apagam dados) e um **backup automático** (`vault.db.vN.bak`)
  é feito antes de qualquer migração.

## [1.0.0] — 2026-07-13

### Adicionado
- Primeiro release: **cofre de senhas local e offline** para Windows e Android.
- Login com **senha mestra + TOTP** (Authy) e códigos de recuperação.
- Criptografia **Argon2id** (KDF) + **AES-256-GCM**; a chave só existe em memória com o cofre desbloqueado.
- **Criptografia total em repouso** — nem títulos, IPs ou comandos ficam legíveis no banco.
- Credenciais, inventário de servidores + comandos SSH, tags, favoritos e busca instantânea.
- Gerador de senhas, medidor de força e detecção de duplicatas.
- **Backup criptografado** (`.vault`), auto-lock e limpeza automática do clipboard.
- Identidade visual **"Steel & Gold"**.

[1.0.1]: https://github.com/leozinhoszg/Keyring/releases/tag/v1.0.1
[1.0.0]: https://github.com/leozinhoszg/Keyring/releases/tag/v1.0.0
