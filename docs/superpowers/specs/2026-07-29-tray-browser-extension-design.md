# Design: Bandeja do sistema + extensão de navegador para salvar logins

**Data:** 2026-07-29
**Status:** Aprovado pelo usuário (design verbal); aguardando revisão do spec escrito

## Objetivo

Deixar o keyring residente na bandeja do sistema do Windows e, ao fazer login em um
site no Chrome ou Edge, perguntar se o usuário deseja salvar o login e a senha no
cofre.

## Decisões de escopo (respostas do usuário)

- Integração completa: bandeja **e** extensão de navegador.
- Navegadores: **Chrome + Edge** (Chromium/Manifest V3, uma base de código).
- Função da extensão nesta versão: **apenas oferecer salvar** login/senha.
  Preenchimento automático e atualização de credencial existente ficam fora do escopo.
- Cofre travado no momento do salvamento: **restaurar a janela e pedir desbloqueio**
  (senha mestra ou Windows Hello); depois salvar.
- Bandeja: **fechar (X) minimiza para a bandeja**; **iniciar junto com o Windows**
  (já oculto). Não haverá bloqueio automático ao minimizar.
- Comunicação: **WebSocket local** em `127.0.0.1` com pareamento por token
  (não Native Messaging).
- Distribuição da extensão: **modo desenvolvedor** ("Load unpacked"). Publicação na
  Chrome Web Store fora do escopo.

## Arquitetura

Três componentes:

1. **App Flutter (keyring)** — modo bandeja, auto-início com o Windows e servidor
   WebSocket local que recebe pedidos de salvamento.
2. **Extensão de navegador** — projeto novo em `browser-extension/` no repositório.
   Detecta envio de formulários de login e pergunta se o usuário quer salvar.
3. **Protocolo** — mensagens JSON sobre WebSocket em `127.0.0.1`, com pareamento por
   token na primeira conexão.

### App: bandeja e auto-início

- Pacotes `tray_manager` + `window_manager`.
  - Clicar no **X esconde a janela**; o app segue vivo na bandeja.
  - Ícone da bandeja com menu: **Abrir keyring / Bloquear cofre / Sair**.
  - "Sair" encerra o processo de verdade.
- Pacote `launch_at_startup`.
  - Opção nas Configurações: "Iniciar com o Windows".
  - Quando iniciado pelo sistema, o app abre já oculto na bandeja
    (argumento de linha de comando `--hidden`).

### App: servidor local e protocolo

- WebSocket em `127.0.0.1`, tentando as portas `19457`, `19458` e `19459`, nessa
  ordem; a extensão conhece a mesma lista e varre ao conectar.
- **Pareamento:** na primeira conexão, o app mostra um diálogo
  "A extensão quer se conectar — permitir?". Ao aceitar, o app gera um token
  aleatório; a extensão o guarda (`chrome.storage.local`) e o apresenta em toda
  mensagem futura. No app, o token fica no `flutter_secure_storage`.
  Mensagens sem token válido são recusadas.
- **Operações do protocolo:** somente escrita —
  `save-credential { url, username, password }` e o handshake de pareamento.
  O servidor **nunca** envia segredos do cofre para fora; isso reduz o risco do
  modelo WebSocket (um processo local malicioso poderia no máximo injetar pedidos
  de salvamento, que ainda exigem confirmação/desbloqueio no app).

### Extensão: detecção e fluxo de salvamento

1. Content script observa formulários que contêm campo de senha; no envio, captura
   URL da página, usuário e senha.
2. A extensão mostra um banner discreto no topo da página:
   **"Salvar este login no keyring?" [Salvar] [Agora não]**.
3. Ao clicar Salvar, o service worker (background) envia `save-credential` ao app
   via WebSocket.
4. No app:
   - Cofre **destravado** → salva direto uma nova credencial
     (título = domínio do site; campos: URL, usuário, senha) e responde `ok`;
     o banner confirma.
   - Cofre **travado** → o app restaura a janela, pede desbloqueio
     (senha mestra ou Windows Hello, já existentes) e então salva.
5. App não está rodando / WebSocket desconectado → a extensão fica silenciosa
   (não mostra banner).

## Erros e casos-limite

- **Porta ocupada** → o app tenta a próxima porta da lista (`19457` → `19458` →
  `19459`); a extensão varre a mesma lista ao conectar.
- **Usuário fecha o diálogo de desbloqueio** → pedido descartado; a extensão avisa
  "não salvo".
- **Site já existe no cofre** → salva como nova entrada (dedupe/atualização fora do
  escopo desta versão).

## Fases de implementação

- **Fase A:** bandeja + auto-início (entregável por si só).
- **Fase B:** servidor WebSocket + protocolo + fluxo de salvamento no app.
- **Fase C:** extensão Chrome/Edge (content script, background, pareamento, banner).

## Testes

- **Fases A/B:** testes unitários Dart para o protocolo (parsing/validação de
  mensagens, verificação de token) e para o fluxo de salvamento no repositório do
  cofre.
- **Fase C:** teste manual da extensão via "Load unpacked" no Chrome/Edge em sites
  reais de login.
