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

# Assinatura do executável Windows

Assunto diferente do APK: são sistemas de assinatura sem relação um com o outro. A chave
`.jks` acima não serve para o Windows, e o certificado abaixo não serve para o Android.

## Por que o SmartScreen barra o app

Sem assinatura, o Windows exibe **"O Windows protegeu o computador"** a cada versão nova.
O SmartScreen decide por três critérios, e um `.exe` não assinado falha em todos:

- **Certificado de code signing** — é o que identifica o editor.
- **Reputação do arquivo** — cada build tem um hash novo, sem histórico.
- **Marca de origem** — arquivos baixados da internet carregam o *Mark of the Web*, que
  dispara a checagem. Por isso o `.zip` do release aciona o aviso e uma cópia local, não.

## O que a assinatura resolve, e até onde

| Certificado | Custo (Brasil, 1 ano) | Alcance |
|---|---|---|
| Autoassinado | zero | Só nas máquinas onde ele for instalado como confiável |
| OV de uma CA | R$ 1.400 – 3.000 + token | Identifica o editor, mas **não garante** que o aviso suma |
| EV de uma CA | R$ 2.200 – 3.600 + token | Idem — o EV deixou de dar vantagem no SmartScreen |

Desde 2023 as regras do CA/Browser Forum exigem que a chave privada fique em hardware, então
qualquer certificado de CA vem com token USB ou HSM em nuvem, e a validade máxima caiu para
1 ano — o custo é recorrente.

### Comprar um certificado não garante que o aviso desapareça

Durante anos o EV dava reputação imediata no SmartScreen. **A Microsoft mudou isso.** Hoje
todo binário assinado — EV ou OV — precisa acumular reputação organicamente, por downloads e
execuções sem incidentes. Um app com poucos usuários pode continuar exibindo o aviso
indefinidamente, mesmo assinado e pago. Boa parte dos vendedores ainda anuncia "reputação
imediata"; a documentação da Microsoft diz o contrário.

Consequência prática: para um projeto pequeno, o certificado pago resolve o "editor
desconhecido", mas não necessariamente a tela do SmartScreen. Pesar isso antes de assinar
um contrato anual.

### ICP-Brasil não serve

Certificados A1/A3 (Certisign, Serasa, Safeweb, Soluti, VALID, Bry) são para NF-e, e-CNPJ e
assinatura de documentos. A ICP-Brasil **proibiu** a emissão de certificados de assinatura de
código; os emitidos antes da resolução valem até expirar. Não há caminho por aí — as CAs que
funcionam são as internacionais (Sectigo, DigiCert, GlobalSign), vendidas no Brasil por
revendas.

### Azure Artifact Signing não serve para o Brasil

O serviço da Microsoft (ex-Trusted Signing) sairia por ~US$ 10/mês, mas emite certificados de
confiança pública apenas para organizações nos EUA, Canadá, União Europeia, Reino Unido,
Austrália, Nova Zelândia, Japão, Coreia do Sul, Singapura, Suíça, Noruega e Israel —
desenvolvedores individuais, só EUA e Canadá. **O Brasil está fora**, e o crédito da conta
gratuita não muda isso: a barreira é a validação de identidade.

Não se engane com a tabela de regiões da documentação: "Brazil South" aparece como região
suportada, mas isso é onde o recurso é hospedado, não quem pode se cadastrar.

Resta o **Private Trust**, sem restrição geográfica — só que ele é o mesmo modelo do
autoassinado (vale apenas onde o certificado for instalado), com a chave em HSM gerenciado.
Pagar por isso só compensa se a gestão da chave for o problema; para o SmartScreen, não muda nada.

## Assinando

Requer o Windows SDK (`winget install --id Microsoft.WindowsSDK`), que traz o `signtool.exe`.

```powershell
flutter build windows --release
.\tool\assinar-windows.ps1                    # gera o certificado na primeira vez
```

Para o aviso sumir **nesta máquina**, o certificado precisa entrar na lista de editores
confiáveis — num terminal como Administrador:

```powershell
.\tool\assinar-windows.ps1 -InstalarConfianca
```

Em outras máquinas, repita esse passo nelas ou distribua o certificado por GPO.

Com um certificado comprado, o fluxo é o mesmo:

```powershell
.\tool\assinar-windows.ps1 -Pfx C:\caminho\keyring-ev.pfx
```

> **Guarde o `.pfx` e a senha com backup.** Trocar de certificado faz o Windows tratar as
> versões novas como de **outro editor**, e a reputação acumulada volta a zero.

O script sempre aplica **carimbo de tempo**: sem ele, as assinaturas param de valer quando o
certificado expira, inclusive nas versões já distribuídas.

## Saída de emergência para quem baixar

Enquanto não houver certificado de CA, quem baixar o `.zip` verá o aviso. O caminho é
**Mais informações → Executar assim mesmo** — o botão só aparece depois do "Mais informações",
por isso o diálogo parece oferecer apenas "Não executar".

Alternativa para quem prefere linha de comando, removendo a marca de origem do arquivo baixado:

```powershell
Unblock-File .\keyring-1.2.0-windows-x64.zip
```
