# Changelog

Todas as mudanças notáveis do **Keyring** são documentadas aqui.
O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/) e o versionamento é [SemVer](https://semver.org/lang/pt-BR/).

## [Não lançado]

## [1.2.0] — 2026-07-29

Rodada de segurança guiada por uma auditoria do código contra as práticas de
criptografia aplicada, OWASP, resiliência e testing.

### Adicionado

- **Recuperação quando o autenticador se perde.** Os códigos de recuperação
  eram gerados e exibidos no setup, mas nenhuma tela os aceitava — quem
  perdesse o Authy perdia o cofre com os códigos na mão. Agora a tela de
  desbloqueio tem "Perdi o acesso ao autenticador": senha mestra + um código
  abrem o cofre e levam direto à reconfiguração do TOTP. Cada código vale uma
  vez, e o segredo antigo é descartado no processo.

- **Códigos de recuperação com 100 bits de entropia** (`XXXXX-XXXXX-XXXXX-XXXXX`),
  contra 40 bits antes, e com hash salgado. Os códigos antigos continuam
  válidos até serem usados.

### Segurança

- **Cada campo cifrado agora é amarrado ao seu lugar** (AAD com o registro e o
  campo de origem). Antes, quem tivesse acesso ao arquivo podia copiar o blob
  da senha de um registro para outro e o app exibia o segredo no lugar errado,
  sem nada acusar. Os blobs passam a carregar a versão do formato, e o cofre é
  convertido automaticamente no primeiro desbloqueio — em uma transação, com o
  formato antigo continuando legível enquanto isso.

- **Tentativas de desbloqueio têm atraso progressivo**, dobrando a cada erro
  até 30 s. As duas primeiras não esperam: errar a senha uma vez é normal.

- **Parâmetros do Argon2 são validados** ao vir do cofre ou de um backup. Um
  arquivo adulterado com `memoryCost` absurdo derrubava o app na abertura.

- **Senha escondida no formulário de credencial**, com botão para revelar.

- **O que foi decifrado para a tela é descartado no auto-lock.** Títulos, URLs
  e projetos continuavam em memória depois de o cofre trancar.

### Corrigido

- **Importar um backup passa a ser tudo ou nada.** Um item malformado no meio
  do arquivo deixava o cofre com metade do backup dentro — estado
  indistinguível do correto, e reimportar duplicava tudo.

- **Backups grandes demais são recusados** antes de decifrar, em vez de serem
  carregados inteiros na memória.

- **Erros que sumiam sem aviso agora aparecem:** falha ao gravar o backup
  (disco cheio, permissão), cofre trancado por inatividade com um formulário
  aberto (o "Salvar" simplesmente não fazia nada), e falhas inesperadas no
  desbloqueio, que deixavam o botão travado para sempre.

### Alterado

- **A derivação da senha mestra saiu da thread da interface.** O Argon2 é
  pesado de propósito e congelava a tela a cada desbloqueio.

## [1.1.1] — 2026-07-29

### Corrigido

- **App abria sem janela em bancos criados durante o desenvolvimento da 1.1.0.**
  Vaults gravados como schema v1 mas que já tinham as colunas do acesso rápido
  faziam a migração v1→v2 falhar com "duplicate column name" — a exceção
  acontecia antes do primeiro frame e o processo ficava vivo com a janela
  invisível. A migração agora verifica quais colunas existem antes de criá-las,
  e é coberta por teste que reproduz exatamente esse banco híbrido. Nenhum dado
  é afetado: o backup automático `.bak` continua sendo feito antes de migrar.

- **Falha na inicialização nunca mais é invisível.** Qualquer erro no bootstrap
  (banco corrompido, migração, disco) agora renderiza uma tela com a causa, o
  aviso de que o vault não foi alterado e um botão para copiar os detalhes —
  em vez de deixar o processo rodando sem janela alguma.

## [1.1.0] — 2026-07-22

### Adicionado

- **Acesso rápido por biometria.** Abrir o cofre passa a exigir só a digital
  (ou o Windows Hello, no desktop), em vez de senha mestra + código do Authy. A
  senha mestra continua sendo pedida a cada 7 dias, e o código do Authy só junto
  dela. O auto-lock de 5 minutos, que antes custava os dois fatores, agora custa
  um toque.

  A chave que abre o cofre fica dividida: metade no cofre de credenciais do
  sistema, metade no `vault.db`. Nenhuma serve sozinha — copiar o `vault.db`
  para outro aparelho não leva o acesso rápido junto.

  No Android a chave é gerada **dentro do Keystore**, presa ao hardware: nunca
  sai do chip, exige autenticação a cada uso e é **destruída automaticamente se
  uma digital nova for cadastrada** no aparelho. No Windows a proteção é do
  Hello sobre o DPAPI, sem equivalente preso ao hardware.

  Ativar em Configurações → Segurança → Acesso rápido.

### Alterado

- **Android 9 (API 28) passa a ser o mínimo**, contra Android 7 antes. É o piso
  da chave biométrica presa ao hardware; abaixo disso o acesso rápido seria
  apenas uma conveniência sem proteção real.

### Segurança

- O PIN/padrão do aparelho é aceito como alternativa à digital, nas duas
  plataformas. Quem souber o PIN do seu celular ou do seu Windows abre o cofre
  sem a senha mestra — trade-off escolhido para não trancar você fora quando o
  sensor não lê o dedo.

## [1.0.2] — 2026-07-22

> **Atualização manual, uma vez só.** Este APK é assinado com uma chave nova e **não instala
> por cima** do que está no seu celular. Antes de atualizar: **Exportar backup**, desinstalar,
> instalar, refazer o setup e **Importar backup**. Passo a passo em [docs/RELEASE.md](docs/RELEASE.md).
> Da próxima versão em diante volta a instalar por cima normalmente.

### Segurança

- **O cofre não vai mais para a nuvem do Google.** O `AndroidManifest.xml` não declarava
  `android:allowBackup`, e o padrão do Android é `true` — o Auto Backup vinha copiando o
  `vault.db` inteiro para a conta Google do usuário, sem aviso. O arquivo ia cifrado, mas
  saía do aparelho e contradizia o "100% no seu dispositivo" prometido no README. Agora
  `allowBackup="false"`, mais um `data_extraction_rules.xml` que fecha também a
  transferência direta entre aparelhos (D2D) — que, no Android 12+, o `allowBackup` sozinho
  **não** bloqueia.

  Efeito colateral desejado: trocar de celular não leva mais o cofre junto. Use **Exportar
  backup** para isso.

- **APK com identidade estável.** O build de release era assinado com a chave de debug, que o
  Gradle recria a cada execução em runner limpo. Cada APK saía com uma identidade diferente,
  então atualizar por cima falhava e a única saída era desinstalar — **apagando o cofre**.
  A assinatura agora vem de `android/key.properties` (local) ou de secrets do repositório
  (CI), nunca versionados.

  Sem chave configurada, o build de release **falha no CI de propósito** e cai para debug
  com aviso na máquina local. O workflow ainda imprime o SHA-256 do certificado ao final,
  para conferir entre releases.

### Adicionado

- **Build de APK na nuvem** via GitHub Actions (`.github/workflows/build-apk.yml`): o APK Android
  passa a ser gerado num ambiente limpo (Ubuntu), sem depender da máquina local nem de exceções de
  antivírus. Disparo manual pela aba Actions ou automático ao criar uma tag `v*`.
- **[docs/RELEASE.md](docs/RELEASE.md)** — como gerar a chave de assinatura, configurar os
  secrets do GitHub e fazer a migração desta versão.

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

[1.1.0]: https://github.com/leozinhoszg/Keyring/releases/tag/v1.1.0
[1.0.2]: https://github.com/leozinhoszg/Keyring/releases/tag/v1.0.2
[1.0.1]: https://github.com/leozinhoszg/Keyring/releases/tag/v1.0.1
[1.0.0]: https://github.com/leozinhoszg/Keyring/releases/tag/v1.0.0
