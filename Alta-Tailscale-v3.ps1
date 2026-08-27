<#
    Alta-Tailscale-v3.ps1
    Descarga, instala y da de alta Tailscale en un equipo Windows de la empresa.

    Convencion de nombres: dentaldata-<iniciales>
    Tag por defecto: tag:docker-etl

    Uso (PowerShell como Administrador):
        .\Alta-Tailscale-v3.ps1
            -> pregunta iniciales y auth key, descarga la ultima version

        .\Alta-Tailscale-v3.ps1 -Iniciales jm -AuthKey "tskey-auth-xxxxx"
            -> sin preguntas

        .\Alta-Tailscale-v3.ps1 -Iniciales jm -Version 1.102.3
            -> fija una version concreta (recomendado en produccion)

        .\Alta-Tailscale-v3.ps1 -Iniciales jm -MsiPath "C:\temp\tailscale.msi"
            -> usa un MSI local, sin descargar
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [ValidatePattern('^[a-zA-Z]{2,4}$')]
    [string]$Iniciales,

    [ValidatePattern('^[a-zA-Z0-9]{2,12}$')]
    [string]$Sufijo,

    [string]$AuthKey,

    # Token de API solo-lectura para comprobar nombres duplicados. Opcional.
    [string]$ApiToken,
    [string]$Tailnet = "-",

    [string]$Tag = "tag:docker-etl",

    # Version concreta a instalar (ej. "1.102.3"). Vacio = ultima estable.
    [string]$Version,

    # MSI local ya descargado. Si se indica, no descarga nada.
    [string]$MsiPath,

    [switch]$SoloInstalar
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$LogFile = Join-Path $env:TEMP "tailscale-install.log"
function Log($m) { Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }

# ------------------------------------------------- 1. Nombre del equipo
while ([string]::IsNullOrWhiteSpace($Iniciales) -or $Iniciales -notmatch '^[a-zA-Z]{2,4}$') {
    Write-Host ""
    Write-Host "Convencion: dentaldata-<iniciales>   ej. Javier Moreno -> jm" -ForegroundColor DarkGray
    $Iniciales = (Read-Host "Iniciales (nombre + apellido, 2-4 letras)").Trim()
    if ($Iniciales -notmatch '^[a-zA-Z]{2,4}$') {
        Write-Host "  Solo letras, entre 2 y 4." -ForegroundColor Yellow
    }
}

$Hostname = "dentaldata-$($Iniciales.ToLower())"
if (-not [string]::IsNullOrWhiteSpace($Sufijo)) { $Hostname += "-$($Sufijo.ToLower())" }
Log "Nombre asignado: $Hostname"

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

        if ($existentes -contains $Hostname.ToLower()) {
            $similares = $existentes | Where-Object { $_ -like "dentaldata-$($Iniciales.ToLower())*" }
            Write-Host ""
            Write-Host "  '$Hostname' YA EXISTE." -ForegroundColor Red
            Write-Host "  Parecidos en uso: $($similares -join ', ')" -ForegroundColor Yellow
            Write-Host "  Usa -Sufijo o iniciales mas largas." -ForegroundColor Yellow
            throw "Nombre duplicado: $Hostname"
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
    # Arquitectura del equipo
    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { 'amd64' }
        'ARM64' { 'arm64' }
        'x86'   { 'x86'   }
        default { 'amd64' }
    }
    Log "Arquitectura detectada: $arch"

    # Version: la indicada, o la ultima estable leida del indice de paquetes
    if ([string]::IsNullOrWhiteSpace($Version)) {
        Log "Consultando la ultima version estable..."
        try {
            $indice = Invoke-WebRequest -Uri "https://pkgs.tailscale.com/stable/" -UseBasicParsing
            $encontradas = [regex]::Matches(
                $indice.Content,
                "tailscale-setup-(\d+\.\d+\.\d+)-$arch\.msi"
            ) | ForEach-Object { $_.Groups[1].Value } | Sort-Object { [version]$_ } -Unique

            if (-not $encontradas) { throw "No he encontrado ningun MSI para '$arch' en el indice." }
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
        Log "El MSI ya estaba descargado en $MsiPath"
    }
    else {
        Log "Descargando $msiUrl ..."
        $progressPreference = 'SilentlyContinue'   # acelera mucho Invoke-WebRequest
        try {
            Invoke-WebRequest -Uri $msiUrl -OutFile $MsiPath -UseBasicParsing
        }
        catch {
            throw "Fallo la descarga: $($_.Exception.Message)"
        }
        $progressPreference = 'Continue'
        $descargado = $true
    }

    # Comprobacion basica de integridad: debe ser un fichero MSI real
    $tam = (Get-Item $MsiPath).Length
    if ($tam -lt 5MB) { throw "El fichero descargado solo pesa $([math]::Round($tam/1MB,1)) MB. Sospechoso." }

    $firma = [IO.File]::ReadAllBytes($MsiPath)[0..7]
    $esOle = ($firma -join ',') -eq '208,207,17,224,161,177,26,225'   # cabecera OLE de un MSI
    if (-not $esOle) { throw "El fichero descargado no es un MSI valido (posible pagina de error)." }

    Log "MSI verificado ($([math]::Round($tam/1MB,1)) MB)."
}

# ------------------------------------------------- 4. Auth key
if (-not $SoloInstalar -and [string]::IsNullOrWhiteSpace($AuthKey)) {
    $secure  = Read-Host -Prompt "Pega la auth key de Tailscale ($Tag)" -AsSecureString
    $AuthKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                   [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}

# ------------------------------------------------- 5. Instalacion silenciosa
Log "Instalando Tailscale..."

$msiArgs = @(
    '/i', "`"$MsiPath`"", '/qn', '/norestart', '/L*v', "`"$LogFile`"",
    'TS_UNATTENDEDMODE=always',
    'TS_ALLOWINCOMINGCONNECTIONS=always',
    'TS_ADMINCONSOLE=hide',
    'TS_EXITNODEMENU=hide',
    'TS_TESTMENU=hide',
    'TS_ONBOARDING_FLOW=hide',
    'TS_NOLAUNCH=1'
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

if ($SoloInstalar) { Log "Instalado sin dar de alta (-SoloInstalar)."; return }

# ------------------------------------------------- 7. Alta en el tailnet
Log "Dando de alta '$Hostname' con $Tag ..."

$upArgs = @(
    'up',
    '--auth-key', $AuthKey,
    '--hostname', $Hostname,
    "--advertise-tags=$Tag",
    '--unattended',
    '--accept-dns=true'
)

$salida = & $exe @upArgs 2>&1
if ($LASTEXITCODE -ne 0) { throw "'tailscale up' fallo: $salida" }

# ------------------------------------------------- 8. Verificacion
Start-Sleep -Seconds 3
$estado = & $exe status --json | ConvertFrom-Json
$ip = ($estado.Self.TailscaleIPs | Where-Object { $_ -notmatch ':' }) -join ', '

Write-Host ""
Log "ALTA COMPLETADA"
Log "  Equipo  : $($estado.Self.HostName)"
Log "  IP      : $ip"
Log "  Tags    : $($estado.Self.Tags -join ', ')"
Log "  Version : $($estado.Version)"
Log "  Estado  : $($estado.BackendState)"
Log "  Log MSI : $LogFile"
