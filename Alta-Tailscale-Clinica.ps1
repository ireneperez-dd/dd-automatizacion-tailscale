<#
    Alta-Tailscale-Clinica.ps1
    Descarga, instala y da de alta Tailscale en un equipo de CLINICA.

    Diferencias respecto al script de equipos internos:
      - Tag: tag:clinic-endpoint (maquina de destino, no de conexion)
      - Bloquea la GUI para que el personal de la clinica no pueda desconectarla
      - NO toca el DNS del equipo (--accept-dns=false) para no romper su red local
      - Configura el servicio para reiniciarse solo si se cae

    Uso (PowerShell como Administrador):
        .\Alta-Tailscale-Clinica.ps1
            -> pregunta el nombre del equipo y la auth key

        .\Alta-Tailscale-Clinica.ps1 -Hostname "clinica-dd-00179" -AuthKey "tskey-auth-xxxxx"
            -> sin preguntas, para desatendido total

        .\Alta-Tailscale-Clinica.ps1 -Hostname "clinica-dd-00179" -AceptarDns
            -> excepcion: aplica el DNS de Tailscale (MagicDNS) en ese equipo
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    # Nombre con el que aparecera el equipo en el tailnet.
    # Si no se indica, el script lo pregunta.
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9\-]{1,61}[a-zA-Z0-9]$')]
    [string]$Hostname,

    [string]$AuthKey,

    # Token de API solo-lectura para detectar nombres duplicados. Opcional.
    [string]$ApiToken,
    [string]$Tailnet = "-",

    [string]$Tag = "tag:clinic-endpoint",

    # Version concreta. Vacio = ultima estable. Recomendado fijarla.
    [string]$Version,

    # MSI local ya descargado (para clinicas sin salida directa a internet)
    [string]$MsiPath,

    # Por defecto NO se aplica el DNS de Tailscale. Activa esto solo si hace falta.
    [switch]$AceptarDns,

    [switch]$SoloInstalar
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$LogFile = Join-Path $env:TEMP "tailscale-install.log"
function Log($m) { Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }

# ------------------------------------------------- 1. Nombre del equipo
$patronNombre = '^[a-zA-Z0-9][a-zA-Z0-9\-]{1,61}[a-zA-Z0-9]$'

while ([string]::IsNullOrWhiteSpace($Hostname) -or $Hostname -notmatch $patronNombre) {
    Write-Host ""
    Write-Host "Nombre del equipo en Tailscale (letras, numeros y guiones)." -ForegroundColor DarkGray
    Write-Host "Ejemplos: dentaldata-host, clinica-dd-00179, dentaldata-d" -ForegroundColor DarkGray
    $Hostname = (Read-Host "Nombre").Trim()

    if ($Hostname -notmatch $patronNombre) {
        Write-Host "  Nombre no valido. Sin espacios, acentos, puntos ni guiones bajos." -ForegroundColor Yellow
        Write-Host "  No puede empezar ni acabar en guion." -ForegroundColor Yellow
        $Hostname = ""
    }
}

$Hostname = $Hostname.ToLower()
Log "Nombre a usar: $Hostname"

# ------------------------------------------------- 2. Comprobar duplicados
if ([string]::IsNullOrWhiteSpace($ApiToken)) {
    Log "AVISO: sin -ApiToken no compruebo si '$Hostname' ya existe."
    if ((Read-Host "Continuar? (s/N)") -notmatch '^[sS]') { Log "Cancelado."; return }
}
else {
    Log "Comprobando nombres en el tailnet..."
    try {
        $url = "https://api.tailscale.com/api/v2/tailnet/$Tailnet/devices"
        $devices = (Invoke-RestMethod -Uri $url -Headers @{ Authorization = "Bearer $ApiToken" }).devices
        $existentes = $devices | ForEach-Object { ($_.name -split '\.')[0].ToLower() }

        while ($existentes -contains $Hostname) {
            Write-Host ""
            Write-Host "  '$Hostname' YA EXISTE en el tailnet." -ForegroundColor Red
            Write-Host "  Si es una REINSTALACION, borra primero el nodo viejo en la consola." -ForegroundColor Yellow
            Write-Host "  Si no, elige otro nombre (o Enter para cancelar)." -ForegroundColor Yellow

            $nuevo = (Read-Host "Nuevo nombre").Trim().ToLower()
            if ([string]::IsNullOrWhiteSpace($nuevo)) { Log "Cancelado."; return }

            if ($nuevo -notmatch $patronNombre) {
                Write-Host "  Nombre no valido." -ForegroundColor Yellow
            }
            else {
                $Hostname = $nuevo
            }
        }
        Log "Nombre libre ($($existentes.Count) equipos en el tailnet)."
    }
    catch [System.Net.WebException] {
        Log "No he podido consultar la API: $($_.Exception.Message). Continuo."
    }
}

# ------------------------------------------------- 3. Obtener el MSI
$descargado = $false

if (-not [string]::IsNullOrWhiteSpace($MsiPath)) {
    if (-not (Test-Path $MsiPath)) { throw "No encuentro el MSI en '$MsiPath'." }
    Log "Usando MSI local: $MsiPath"
}
else {
    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { 'amd64' }
        'ARM64' { 'arm64' }
        'x86'   { 'x86'   }
        default { 'amd64' }
    }
    Log "Arquitectura detectada: $arch"

    if ([string]::IsNullOrWhiteSpace($Version)) {
        Log "Consultando la ultima version estable..."
        try {
            $indice = Invoke-WebRequest -Uri "https://pkgs.tailscale.com/stable/" -UseBasicParsing
            $encontradas = [regex]::Matches(
                $indice.Content, "tailscale-setup-(\d+\.\d+\.\d+)-$arch\.msi"
            ) | ForEach-Object { $_.Groups[1].Value } | Sort-Object { [version]$_ } -Unique
            if (-not $encontradas) { throw "No hay MSI para '$arch' en el indice." }
            $Version = $encontradas[-1]
        }
        catch {
            throw "No he podido determinar la version ($($_.Exception.Message)). Usa -Version o -MsiPath."
        }
    }
    Log "Version a instalar: $Version"

    $msiUrl  = "https://pkgs.tailscale.com/stable/tailscale-setup-$Version-$arch.msi"
    $MsiPath = Join-Path $env:TEMP "tailscale-setup-$Version-$arch.msi"

    if (Test-Path $MsiPath) {
        Log "MSI ya presente en $MsiPath"
    }
    else {
        Log "Descargando $msiUrl ..."
        $progressPreference = 'SilentlyContinue'
        try   { Invoke-WebRequest -Uri $msiUrl -OutFile $MsiPath -UseBasicParsing }
        catch { throw "Fallo la descarga: $($_.Exception.Message)" }
        $progressPreference = 'Continue'
        $descargado = $true
    }

    $tam = (Get-Item $MsiPath).Length
    if ($tam -lt 5MB) { throw "El fichero solo pesa $([math]::Round($tam/1MB,1)) MB. Sospechoso." }
    $firma = [IO.File]::ReadAllBytes($MsiPath)[0..7]
    if (($firma -join ',') -ne '208,207,17,224,161,177,26,225') {
        throw "El fichero descargado no es un MSI valido (posible portal cautivo o pagina de error)."
    }
    Log "MSI verificado ($([math]::Round($tam/1MB,1)) MB)."
}

# ------------------------------------------------- 4. Auth key
if (-not $SoloInstalar -and [string]::IsNullOrWhiteSpace($AuthKey)) {
    Write-Host ""
    Write-Host "  Usa la auth key de CLINICA (la asociada a $Tag)." -ForegroundColor DarkGray
    $secure  = Read-Host -Prompt "Pega la auth key" -AsSecureString
    $AuthKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                   [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}

# ------------------------------------------------- 5. Instalacion silenciosa
Log "Instalando Tailscale (modo kiosco: GUI bloqueada)..."

$msiArgs = @(
    '/i', "`"$MsiPath`"", '/qn', '/norestart', '/L*v', "`"$LogFile`"",

    # Conectividad permanente sin sesion de usuario
    'TS_UNATTENDEDMODE=always',
    'TS_ALLOWINCOMINGCONNECTIONS=always',

    # El personal de la clinica no debe poder cambiar nada
    'TS_PREFERENCESMENU=hide',
    'TS_ADMINCONSOLE=hide',
    'TS_NETWORKDEVICES=hide',
    'TS_EXITNODEMENU=hide',
    'TS_ADVERTISEEXITNODE=never',
    'TS_TESTMENU=hide',
    'TS_ONBOARDING_FLOW=hide',
    'TS_UPDATEMENU=hide',
    'TS_NOLAUNCH=1',

    # Actualizaciones automaticas: no vamos a ir clinica por clinica a mano
    'TS_INSTALLUPDATES=always',

    # No aplicar el DNS de Tailscale salvo que se pida expresamente
    "TS_ENABLEDNS=$(if ($AceptarDns) { 'always' } else { 'never' })",

    # No aceptar subredes anunciadas por otros nodos
    'TS_ENABLESUBNETS=never'
)

$proc = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
switch ($proc.ExitCode) {
    0     { Log "MSI instalado." }
    3010  { Log "MSI instalado. AVISO: requiere reinicio (codigo 3010)." }
    1638  { Log "Ya habia una version instalada. Revisa $LogFile." }
    default { throw "msiexec fallo con codigo $($proc.ExitCode). Log: $LogFile" }
}

if ($descargado) { Remove-Item $MsiPath -Force -ErrorAction SilentlyContinue }

# ------------------------------------------------- 6. Esperar servicio
$exe = Join-Path ${env:ProgramFiles} 'Tailscale\tailscale.exe'
if (-not (Test-Path $exe)) { throw "No encuentro tailscale.exe en '$exe'." }

Log "Esperando al servicio Tailscale..."
$deadline = (Get-Date).AddSeconds(60)
do {
    $svc = Get-Service -Name Tailscale -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') { Start-Service Tailscale -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
} until (($svc -and $svc.Status -eq 'Running') -or (Get-Date) -gt $deadline)

if (-not $svc -or $svc.Status -ne 'Running') { throw "El servicio Tailscale no ha arrancado." }

# ------------------------------------------------- 7. Resiliencia del servicio
# En una clinica no hay nadie que reinicie el servicio si se cae.
Log "Configurando arranque automatico y recuperacion ante fallos..."
Set-Service -Name Tailscale -StartupType Automatic
& sc.exe failure Tailscale reset= 86400 actions= restart/60000/restart/60000/restart/120000 | Out-Null

if ($SoloInstalar) { Log "Instalado sin dar de alta (-SoloInstalar)."; return }

# ------------------------------------------------- 8. Alta en el tailnet
Log "Dando de alta '$Hostname' con $Tag ..."

$upArgs = @(
    'up',
    '--auth-key', $AuthKey,
    '--hostname', $Hostname,
    "--advertise-tags=$Tag",
    '--unattended',
    "--accept-dns=$(if ($AceptarDns) { 'true' } else { 'false' })",
    '--accept-routes=false'
)

$salida = & $exe @upArgs 2>&1
if ($LASTEXITCODE -ne 0) { throw "'tailscale up' fallo: $salida" }

# ------------------------------------------------- 9. Verificacion
Start-Sleep -Seconds 3
$estado = & $exe status --json | ConvertFrom-Json
$ip = ($estado.Self.TailscaleIPs | Where-Object { $_ -notmatch ':' }) -join ', '

Write-Host ""
Log "ALTA DE CLINICA COMPLETADA"
Log "  Equipo  : $($estado.Self.HostName)"
Log "  IP      : $ip"
Log "  Tags    : $($estado.Self.Tags -join ', ')"
Log "  Version : $($estado.Version)"
Log "  Estado  : $($estado.BackendState)"
Log "  DNS TS  : $(if ($AceptarDns) { 'aplicado' } else { 'NO aplicado (red local intacta)' })"
Log "  Log MSI : $LogFile"
Write-Host ""
Log "Comprueba desde un equipo interno:  tailscale ping $Hostname"
