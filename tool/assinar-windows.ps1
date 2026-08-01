# ============================================================================
#  Assinatura do executavel Windows do Keyring
#
#  Sem assinatura, o SmartScreen barra o app a cada versao nova com
#  "O Windows protegeu o computador". Assinar resolve o "editor desconhecido";
#  quanto ao SmartScreen, o alcance depende do certificado usado:
#
#    - Autoassinado (padrao deste script, custo zero): vale nas maquinas onde
#      o certificado for instalado como confiavel. Serve para uso proprio e
#      para uma equipe. NAO ajuda quem baixar de fora.
#
#    - Certificado de uma CA (comprado): vale em qualquer maquina. Use o
#      parametro -Pfx para apontar para ele; o resto do fluxo e identico.
#
#  Uso:
#    .\tool\assinar-windows.ps1                      # gera/usa cert autoassinado
#    .\tool\assinar-windows.ps1 -Pfx C:\cert.pfx     # usa um certificado proprio
#    .\tool\assinar-windows.ps1 -InstalarConfianca   # confia no cert nesta maquina
# ============================================================================

[CmdletBinding()]
param(
  # Executavel a assinar. Por padrao, o build de release local.
  [string]$Exe = "$PSScriptRoot\..\build\windows\x64\runner\Release\keyring.exe",

  # Certificado .pfx proprio (de uma CA). Vazio = usa/gera o autoassinado.
  [string]$Pfx,

  # Senha do .pfx, quando aplicavel.
  [string]$PfxPassword,

  # Onde guardar o certificado autoassinado gerado. Fora do repositorio.
  [string]$PfxGerado = "$HOME\keyring-codesign.pfx",

  # Instala o certificado como raiz confiavel + editor confiavel NESTA maquina.
  # Exige terminal como Administrador. E o passo que faz o aviso sumir aqui.
  [switch]$InstalarConfianca,

  [string]$Assunto = 'CN=Keyring, O=Proma, C=BR',

  # Carimbo de tempo: sem ele a assinatura morre quando o certificado expira.
  [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'

function Passo($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Aviso($msg) { Write-Host "    $msg" -ForegroundColor Yellow }

# --- 1) Localizar o SignTool ------------------------------------------------
$signtool = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match '\\x64\\' } |
  Sort-Object FullName -Descending | Select-Object -First 1
if (-not $signtool) {
  throw "signtool.exe nao encontrado. Instale o Windows SDK:  winget install --id Microsoft.WindowsSDK"
}
Passo "SignTool: $($signtool.FullName)"

if (-not (Test-Path $Exe)) { throw "Executavel nao encontrado: $Exe. Rode antes:  flutter build windows --release" }
$Exe = (Resolve-Path $Exe).Path

# --- 2) Obter o certificado -------------------------------------------------
if ($Pfx) {
  if (-not (Test-Path $Pfx)) { throw "Certificado nao encontrado: $Pfx" }
  $certPath = (Resolve-Path $Pfx).Path
  $certSenha = $PfxPassword
  Passo "Usando certificado proprio: $certPath"
}
else {
  $certPath = $PfxGerado
  if (Test-Path $certPath) {
    Passo "Reaproveitando o certificado autoassinado: $certPath"
    Aviso "Manter o MESMO certificado entre versoes e o que faz o Windows tratar"
    Aviso "todas elas como do mesmo editor. Nao apague esse arquivo."
  }
  else {
    Passo "Gerando certificado autoassinado (valido por 5 anos)"
    # HashAlgorithm sha256 e o minimo aceito hoje; 3 anos e o teto de muitas CAs,
    # mas para autoassinado 5 evita ter que refazer isso cedo demais.
    $cert = New-SelfSignedCertificate `
      -Type CodeSigningCert `
      -Subject $Assunto `
      -KeyAlgorithm RSA -KeyLength 4096 -HashAlgorithm sha256 `
      -CertStoreLocation Cert:\CurrentUser\My `
      -NotAfter (Get-Date).AddYears(5)

    $senha = Read-Host 'Senha para proteger o .pfx gerado' -AsSecureString
    Export-PfxCertificate -Cert $cert -FilePath $certPath -Password $senha | Out-Null
    # Sai do store: a partir daqui o .pfx e a fonte de verdade, e ele tem backup.
    Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force
    $certSenha = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($senha))
    Aviso "Guarde $certPath e a senha com backup. Perder = todas as versoes"
    Aviso "futuras viram 'outro editor' para o Windows."
  }
  if (-not $certSenha) {
    $s = Read-Host "Senha do certificado ($certPath)" -AsSecureString
    $certSenha = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
  }
}

# --- 3) Assinar -------------------------------------------------------------
Passo "Assinando $Exe"
$args = @('sign', '/fd', 'sha256', '/f', $certPath)
if ($certSenha) { $args += @('/p', $certSenha) }
$args += @('/tr', $TimestampUrl, '/td', 'sha256', '/v', $Exe)
& $signtool.FullName @args
if ($LASTEXITCODE -ne 0) { throw "signtool falhou (codigo $LASTEXITCODE)" }

# --- 4) Confiar nesta maquina (opcional) ------------------------------------
if ($InstalarConfianca) {
  $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $admin) { throw "-InstalarConfianca exige um terminal como Administrador." }

  Passo 'Instalando o certificado como confiavel nesta maquina'
  $senhaSec = ConvertTo-SecureString $certSenha -AsPlainText -Force
  # Raiz confiavel: valida a cadeia. Editores confiaveis: e o que cala o aviso.
  Import-PfxCertificate -FilePath $certPath -CertStoreLocation Cert:\LocalMachine\Root -Password $senhaSec | Out-Null
  Import-PfxCertificate -FilePath $certPath -CertStoreLocation Cert:\LocalMachine\TrustedPublisher -Password $senhaSec | Out-Null
  Aviso 'Para outras maquinas, repita este passo nelas (ou distribua por GPO).'
}

# --- 5) Conferir ------------------------------------------------------------
$sig = Get-AuthenticodeSignature $Exe
Passo "Resultado: $($sig.Status)"
Write-Host "    Editor: $($sig.SignerCertificate.Subject)"
if ($sig.TimeStamperCertificate) { Write-Host "    Carimbo de tempo: OK" }

if ($sig.Status -eq 'UnknownError' -or $sig.Status -eq 'NotSigned') {
  throw "A assinatura nao foi aplicada: $($sig.StatusMessage)"
}
if ($sig.Status -ne 'Valid') {
  Aviso "Status '$($sig.Status)' e esperado para certificado autoassinado ainda"
  Aviso "nao instalado como confiavel. Rode de novo com -InstalarConfianca."
}
