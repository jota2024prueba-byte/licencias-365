<#
 NAVAJA SUIZA - Taller de servicio TI (v0.1)
 - Solo componentes nativos de Windows (PowerShell 5.1 + WPF). Sin dependencias.
 - Requiere administrador local (se auto-eleva).
 - IA opcional con Gemini (API key gratuita de Google AI Studio).
 - El archivo es ASCII a proposito: asi funciona igual con "irm URL | iex".

 USO LOCAL : clic derecho > Ejecutar con PowerShell (o: powershell -ExecutionPolicy Bypass -File .\NavajaSuiza.ps1)
 USO NUBE  : sube este archivo a un repositorio, pon la URL raw en $ScriptUrl y ejecuta:
             irm https://raw.githubusercontent.com/USUARIO/REPO/main/NavajaSuiza.ps1 | iex
#>

$ScriptUrl = ''   # URL raw del script en la nube (opcional, para auto-elevar desde la nube)

# ---------- Auto-elevacion ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($ScriptUrl) {
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"irm '$ScriptUrl' | iex`""
    } elseif ($PSCommandPath) {
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    } else {
        Write-Host 'Abre PowerShell como administrador y vuelve a ejecutar.'
    }
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------- Configuracion (API key cifrada con DPAPI, por usuario de Windows) ----------
$cfgDir  = Join-Path $env:APPDATA 'NavajaSuiza'
$cfgFile = Join-Path $cfgDir 'config.json'
$logDir  = 'C:\ProgramData\NavajaSuiza\logs'

function Get-Cfg {
    if (Test-Path $cfgFile) { try { return (Get-Content $cfgFile -Raw | ConvertFrom-Json) } catch {} }
    [pscustomobject]@{ Key = ''; Model = 'gemini-2.5-flash' }
}
function Get-ApiKey {
    $c = Get-Cfg
    if (-not $c.Key) { return '' }
    try {
        $s = ConvertTo-SecureString $c.Key
        [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
    } catch { '' }
}

# ---------- Funciones compartidas que viajan al job (IA) ----------
$Common = @'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Hide-Sensitive([string]$t) {
    if (-not $t) { return '' }
    $t = $t -replace [regex]::Escape($env:COMPUTERNAME), '<EQUIPO>'
    $t = $t -replace [regex]::Escape($env:USERNAME), '<USUARIO>'
    $t = $t -replace '\b\d{1,3}(\.\d{1,3}){3}\b', '<IP>'
    $t = $t -replace '([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}', '<MAC>'
    $t
}
function Invoke-Gemini([string]$Prompt, [string]$ApiKey, [string]$Model) {
    if (-not $ApiKey) { return 'Falta la API key de Gemini. Usa el boton "API Gemini" (arriba a la derecha).' }
    $uri  = "https://generativelanguage.googleapis.com/v1beta/models/${Model}:generateContent"
    $body = @{ contents = @(@{ parts = @(@{ text = (Hide-Sensitive $Prompt) }) }) } | ConvertTo-Json -Depth 6
    try {
        $r = Invoke-RestMethod -Uri $uri -Method Post -Headers @{ 'x-goog-api-key' = $ApiKey } `
             -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 90
        ($r.candidates[0].content.parts | ForEach-Object { $_.text }) -join "`n"
    } catch { "Error Gemini: $($_.Exception.Message)" }
}
'@

$JobWrapper = {
    param($common, $toolText, $a, $b, $c, $d)
    $ErrorActionPreference = 'Continue'
    . ([scriptblock]::Create($common))
    & ([scriptblock]::Create($toolText)) $a $b $c $d *>&1 |
        ForEach-Object { (($_ | Out-String -Width 200) -replace "`0", '').TrimEnd() }
}

# ---------- Catalogo de herramientas ----------
# Nivel: 1 = basico, 2 = avanzado, 3 = experto. Cada script recibe: $InputText $ApiKey $Model $LastOutput
function T {
    param($Category, $Name, [int]$Level, $Desc, [scriptblock]$Do, [switch]$Confirm)
    [pscustomobject]@{ Category = $Category; Name = $Name; Level = $Level; Desc = $Desc; Do = $Do; Confirm = [bool]$Confirm }
}

$Tools = @(

# ===== DIAGNOSTICO =====
T 'Diagnostico' 'Inventario del equipo' 1 'Modelo, serial, BIOS, SO, CPU, RAM, discos y ultimo arranque.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    $cs=Get-CimInstance Win32_ComputerSystem; $os=Get-CimInstance Win32_OperatingSystem
    $bios=Get-CimInstance Win32_BIOS; $cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
    [pscustomobject]@{
        Equipo=$env:COMPUTERNAME; Fabricante=$cs.Manufacturer; Modelo=$cs.Model; Serial=$bios.SerialNumber
        BIOS=$bios.SMBIOSBIOSVersion; SO=$os.Caption; Version=$os.Version; CPU=$cpu.Name
        'RAM GB'=[math]::Round($cs.TotalPhysicalMemory/1GB,1); 'Ultimo arranque'=$os.LastBootUpTime; Usuario=$cs.UserName
    } | Format-List | Out-String -Width 200
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
        Select-Object DeviceID,@{n='GB';e={[math]::Round($_.Size/1GB)}},@{n='Libre GB';e={[math]::Round($_.FreeSpace/1GB)}} |
        Format-Table -Auto | Out-String -Width 200
}
T 'Diagnostico' 'Salud de discos' 1 'Estado, tipo, temperatura y errores de cada disco fisico.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    Get-PhysicalDisk | Select-Object FriendlyName,MediaType,HealthStatus,OperationalStatus,@{n='GB';e={[math]::Round($_.Size/1GB)}} | Format-Table -Auto | Out-String -Width 200
    try { Get-PhysicalDisk | Get-StorageReliabilityCounter | Select-Object DeviceId,Temperature,Wear,ReadErrorsTotal,WriteErrorsTotal,PowerOnHours | Format-Table -Auto | Out-String -Width 200 } catch { 'Contadores de fiabilidad no disponibles en este disco.' }
}
T 'Diagnostico' 'Errores recientes (3 dias)' 1 'Errores criticos y de nivel error en Sistema y Aplicacion.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    $ev = Get-WinEvent -FilterHashtable @{LogName='System','Application';Level=1,2;StartTime=(Get-Date).AddDays(-3)} -MaxEvents 40 -ErrorAction SilentlyContinue
    if (-not $ev) { 'Sin errores en los ultimos 3 dias.'; return }
    $ev | Select-Object TimeCreated,ProviderName,Id,@{n='Mensaje';e={($_.Message -split "`n")[0]}} | Format-Table -Wrap -Auto | Out-String -Width 200
}
T 'Diagnostico' 'Pantallazos azules (BSOD)' 2 'Eventos de reinicio inesperado y volcados de memoria recientes.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    Get-WinEvent -FilterHashtable @{LogName='System';Id=41,1001,6008} -MaxEvents 15 -ErrorAction SilentlyContinue |
        Select-Object TimeCreated,Id,ProviderName,@{n='Mensaje';e={($_.Message -split "`n")[0]}} | Format-Table -Wrap -Auto | Out-String -Width 200
    Get-ChildItem "$env:windir\Minidump" -ErrorAction SilentlyContinue | Select-Object Name,Length,LastWriteTime | Format-Table -Auto | Out-String -Width 200
}
T 'Diagnostico' 'Informe de bateria' 1 'Genera el informe HTML de bateria (capacidad de diseno vs actual).' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    $f = Join-Path $env:TEMP 'battery-report.html'
    powercfg /batteryreport /output $f
    if (Test-Path $f) { Invoke-Item $f; "Informe abierto: $f" }
}
T 'Diagnostico' 'Programas de inicio' 1 'Lista lo que arranca con Windows (causa comun de lentitud).' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    Get-CimInstance Win32_StartupCommand | Select-Object Name,Command,Location,User | Format-Table -Wrap -Auto | Out-String -Width 200
}
T 'Diagnostico' 'Procesos que mas consumen' 1 'Top 15 por CPU y memoria.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    'TOP CPU'; Get-Process | Sort-Object CPU -Descending | Select-Object -First 15 Name,Id,@{n='CPU s';e={[math]::Round($_.CPU)}},@{n='RAM MB';e={[math]::Round($_.WS/1MB)}} | Format-Table -Auto | Out-String -Width 200
    'TOP RAM'; Get-Process | Sort-Object WS -Descending | Select-Object -First 10 Name,Id,@{n='RAM MB';e={[math]::Round($_.WS/1MB)}} | Format-Table -Auto | Out-String -Width 200
}

# ===== REPARACION =====
T 'Reparacion' 'SFC /scannow' 2 'Verifica y repara archivos de sistema protegidos.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    sfc /scannow
} -Confirm
T 'Reparacion' 'DISM RestoreHealth' 2 'Repara la imagen de Windows (puede tardar varios minutos).' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    DISM /Online /Cleanup-Image /RestoreHealth
} -Confirm
T 'Reparacion' 'CHKDSK (solo lectura)' 2 'Analiza C: sin modificar nada.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    chkdsk C:
}
T 'Reparacion' 'Limpiar temporales' 1 'Borra temporales de usuario y Windows con mas de 1 dia.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    $lim=(Get-Date).AddDays(-1); $tot=0
    foreach ($p in @($env:TEMP,"$env:windir\Temp")) {
        Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object LastWriteTime -lt $lim |
            ForEach-Object { $tot += $_.Length; Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
    }
    'Espacio aprox. liberado: {0} MB' -f [math]::Round($tot/1MB,1)
} -Confirm
T 'Reparacion' 'Reset Windows Update' 2 'Detiene servicios, renombra SoftwareDistribution/catroot2 y reinicia.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    $svcs='wuauserv','bits','cryptsvc','msiserver'
    $svcs | ForEach-Object { Stop-Service $_ -Force -ErrorAction SilentlyContinue }
    $ts = Get-Date -Format yyyyMMddHHmm
    foreach ($d in "$env:windir\SoftwareDistribution","$env:windir\System32\catroot2") {
        if (Test-Path $d) { Rename-Item $d "$d.old$ts" -ErrorAction Continue }
    }
    $svcs | ForEach-Object { Start-Service $_ -ErrorAction SilentlyContinue }
    'Windows Update restablecido. Vuelve a buscar actualizaciones.'
} -Confirm
T 'Reparacion' 'Reiniciar Explorador' 1 'Reinicia explorer.exe (barra de tareas / escritorio congelado).' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    'Explorador reiniciado.'
}

# ===== RED =====
T 'Red' 'Configuracion IP' 1 'ipconfig /all.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    ipconfig /all
}
T 'Red' 'Ping + DNS (usa Entrada)' 1 'Prueba conectividad al host de Entrada (por defecto 8.8.8.8) y resolucion DNS.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    $h = if ($InputText) { $InputText.Trim() } else { '8.8.8.8' }
    Test-NetConnection $h -WarningAction SilentlyContinue | Format-List ComputerName,RemoteAddress,PingSucceeded,@{n='ms';e={$_.PingReplyDetails.RoundtripTime}} | Out-String -Width 200
    try { Resolve-DnsName google.com -ErrorAction Stop | Select-Object Name,Type,IPAddress | Format-Table -Auto | Out-String -Width 200 } catch { 'DNS: fallo la resolucion de google.com' }
}
T 'Red' 'Traceroute (usa Entrada)' 2 'tracert al host de Entrada.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    $h = if ($InputText) { $InputText.Trim() } else { '8.8.8.8' }
    tracert -d -h 20 $h
}
T 'Red' 'Flush DNS + renovar IP' 1 'ipconfig /flushdns, /release y /renew.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    ipconfig /flushdns; ipconfig /release; ipconfig /renew
} -Confirm
T 'Red' 'Reset pila de red' 2 'netsh winsock reset + int ip reset (requiere reinicio).' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    netsh winsock reset; netsh int ip reset
    'Reinicia el equipo para aplicar los cambios.'
} -Confirm
T 'Red' 'Informe WiFi' 2 'Estado de la conexion inalambrica y reporte WLAN.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    netsh wlan show interfaces
    netsh wlan show wlanreport
    'Reporte: C:\ProgramData\Microsoft\Windows\WlanReport\wlan-report-latest.html'
}
T 'Red' 'Puertos en escucha' 2 'Puertos TCP abiertos y el proceso que los usa.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    Get-NetTCPConnection -State Listen | Sort-Object LocalPort |
        Select-Object LocalAddress,LocalPort,OwningProcess,@{n='Proceso';e={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name}} |
        Format-Table -Auto | Out-String -Width 200
}

# ===== IMPRESORAS =====
T 'Impresoras' 'Listar impresoras y puertos' 1 'Impresoras instaladas, driver, puerto e IP.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    Get-Printer | Select-Object Name,DriverName,PortName,PrinterStatus | Format-Table -Auto | Out-String -Width 200
    Get-PrinterPort | Select-Object Name,PrinterHostAddress | Format-Table -Auto | Out-String -Width 200
}
T 'Impresoras' 'Reiniciar spooler y limpiar cola' 1 'Soluciona trabajos atascados.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    Stop-Service Spooler -Force
    Remove-Item "$env:windir\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
    Start-Service Spooler
    'Spooler reiniciado y cola vaciada.'
} -Confirm
T 'Impresoras' 'Trabajos en cola' 1 'Muestra los trabajos pendientes de cada impresora.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    $j = Get-Printer | ForEach-Object { Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue }
    if ($j) { $j | Select-Object PrinterName,DocumentName,UserName,JobStatus | Format-Table -Auto | Out-String -Width 200 } else { 'Sin trabajos en cola.' }
}
T 'Impresoras' 'Pagina de prueba (usa Entrada)' 1 'Imprime pagina de prueba en la impresora cuyo nombre esta en Entrada.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    if (-not $InputText) { 'Escribe en Entrada el nombre exacto de la impresora.'; return }
    rundll32 printui.dll,PrintUIEntry /k /n "$($InputText.Trim())"
    'Pagina de prueba enviada.'
}

# ===== SEGURIDAD =====
T 'Seguridad' 'Estado de Defender' 1 'Proteccion en tiempo real, firmas y ultimo escaneo.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    Get-MpComputerStatus | Select-Object AntivirusEnabled,RealTimeProtectionEnabled,AntivirusSignatureLastUpdated,QuickScanEndTime,FullScanEndTime | Format-List | Out-String -Width 200
}
T 'Seguridad' 'Firmas + escaneo rapido' 2 'Actualiza firmas de Defender y lanza escaneo rapido.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    Update-MpSignature; Start-MpScan -ScanType QuickScan
    $t = Get-MpThreatDetection
    if ($t) { $t | Select-Object InitialDetectionTime,ThreatID,Resources | Format-Table -Wrap -Auto | Out-String -Width 200 } else { 'Escaneo terminado: sin amenazas detectadas.' }
} -Confirm
T 'Seguridad' 'Estado BitLocker' 2 'Estado de cifrado de unidades.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    manage-bde -status
}
T 'Seguridad' 'Firewall' 1 'Perfiles de firewall y su estado.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    Get-NetFirewallProfile | Select-Object Name,Enabled,DefaultInboundAction,DefaultOutboundAction | Format-Table -Auto | Out-String -Width 200
}
T 'Seguridad' 'Usuarios locales y admins' 2 'Cuentas locales y miembros del grupo Administradores.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    Get-LocalUser | Select-Object Name,Enabled,LastLogon,PasswordLastSet | Format-Table -Auto | Out-String -Width 200
    'ADMINISTRADORES LOCALES'
    Get-LocalGroupMember -SID S-1-5-32-544 | Select-Object Name,ObjectClass,PrincipalSource | Format-Table -Auto | Out-String -Width 200
}

# ===== SOFTWARE =====
T 'Software' 'Programas instalados' 1 'Lista de software instalado con version.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    $k='HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object DisplayName | Sort-Object DisplayName |
        Select-Object DisplayName,DisplayVersion,Publisher | Format-Table -Auto | Out-String -Width 200
}
T 'Software' 'Parches instalados' 1 'Ultimas 15 actualizaciones de Windows instaladas.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 15 HotFixID,Description,InstalledOn | Format-Table -Auto | Out-String -Width 200
}
T 'Software' 'Actualizaciones pendientes (winget)' 2 'Lista aplicaciones con actualizacion disponible.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    winget upgrade --accept-source-agreements
}
T 'Software' 'Actualizar todo (winget)' 3 'Actualiza todas las aplicaciones compatibles en modo silencioso.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    winget upgrade --all --silent --accept-source-agreements --accept-package-agreements
} -Confirm

# ===== IA CON GEMINI =====
T 'IA con Gemini' 'Diagnosticar equipo con IA' 1 'Describe el sintoma en Entrada: recoge datos del equipo y pide causas y pasos a Gemini.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    $os=Get-CimInstance Win32_OperatingSystem; $cs=Get-CimInstance Win32_ComputerSystem
    $ctx=@()
    $ctx+="Equipo: $($cs.Manufacturer) $($cs.Model) | SO: $($os.Caption) $($os.Version) | RAM GB: $([math]::Round($cs.TotalPhysicalMemory/1GB,1)) | Ultimo arranque: $($os.LastBootUpTime)"
    $ctx+='Discos:'
    $ctx+=(Get-PhysicalDisk | ForEach-Object { "$($_.FriendlyName) $($_.MediaType) $($_.HealthStatus)" })
    $ctx+=(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { "$($_.DeviceID) libre $([math]::Round($_.FreeSpace/1GB))GB de $([math]::Round($_.Size/1GB))GB" })
    $ctx+='Errores recientes (3 dias):'
    $ctx+=(Get-WinEvent -FilterHashtable @{LogName='System','Application';Level=1,2;StartTime=(Get-Date).AddDays(-3)} -MaxEvents 25 -ErrorAction SilentlyContinue | ForEach-Object { "$($_.TimeCreated) $($_.ProviderName) Id$($_.Id): $(($_.Message -split "`n")[0])" })
    $ctx+='Top procesos por RAM:'
    $ctx+=(Get-Process | Sort-Object WS -Descending | Select-Object -First 8 | ForEach-Object { "$($_.Name) $([math]::Round($_.WS/1MB))MB" })
    $p = "Eres un tecnico de soporte TI senior. Analiza este resumen de un equipo Windows y el sintoma reportado. Entrega: 1) causas probables ordenadas, 2) pasos concretos de verificacion y reparacion con comandos nativos de Windows, 3) cuando escalar. Responde en espanol, conciso.`nSintoma: $InputText`n`n$($ctx -join "`n")"
    Invoke-Gemini $p $ApiKey $Model
}
T 'IA con Gemini' 'Preguntar a la IA' 1 'Escribe tu pregunta tecnica en Entrada.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    if (-not $InputText) { 'Escribe tu pregunta en el campo Entrada.'; return }
    Invoke-Gemini "Eres un tecnico de soporte TI senior en Windows. Responde en espanol, practico y conciso. Pregunta: $InputText" $ApiKey $Model
}
T 'IA con Gemini' 'Explicar ultima salida' 1 'Gemini interpreta el resultado de la ultima herramienta ejecutada.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    if (-not $LastOutput) { 'Ejecuta primero una herramienta de diagnostico.'; return }
    $t=$LastOutput; if ($t.Length -gt 12000) { $t=$t.Substring($t.Length-12000) }
    Invoke-Gemini "Eres tecnico TI senior. Explica en espanol claro esta salida de diagnostico de Windows: que es anormal, causa probable y siguientes pasos. Contexto del tecnico: $InputText`n`n$t" $ApiKey $Model
}
T 'IA con Gemini' 'Generar script PowerShell' 2 'Describe en Entrada lo que quieres automatizar. Solo lo genera: NO lo ejecuta.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    if (-not $InputText) { 'Describe en Entrada lo que necesitas.'; return }
    Invoke-Gemini "Escribe un script PowerShell 5.1 que use solo cmdlets nativos de Windows para: $InputText. Comentarios en espanol, manejo de errores, y confirmacion previa antes de cualquier accion destructiva. Devuelve primero el script y luego 2 lineas de explicacion." $ApiKey $Model
}
T 'IA con Gemini' 'Redactar nota de ticket' 1 'Entrada = lo que hiciste. Usa la ultima salida para redactar nota y mensaje al usuario.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    $t=$LastOutput; if ($t -and $t.Length -gt 8000) { $t=$t.Substring($t.Length-8000) }
    Invoke-Gemini "Redacta en espanol una nota de ticket (Sintoma, Diagnostico, Accion, Resultado) y un mensaje breve y amable para el usuario final. Acciones del tecnico: $InputText`n`nSalida de herramientas:`n$t" $ApiKey $Model
}

# ===== TALLER =====
T 'Taller' 'Reporte HTML del equipo' 1 'Genera un reporte de ingreso/entrega (equipo, discos, parches) y lo abre.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    $dir='C:\ProgramData\NavajaSuiza\reportes'; New-Item -ItemType Directory -Force $dir | Out-Null
    $f=Join-Path $dir ("{0}-{1}.html" -f $env:COMPUTERNAME,(Get-Date -Format 'yyyyMMdd-HHmm'))
    $cs=Get-CimInstance Win32_ComputerSystem; $os=Get-CimInstance Win32_OperatingSystem; $bios=Get-CimInstance Win32_BIOS
    $a=[pscustomobject]@{Equipo=$env:COMPUTERNAME;Fabricante=$cs.Manufacturer;Modelo=$cs.Model;Serial=$bios.SerialNumber;SO=$os.Caption;'RAM GB'=[math]::Round($cs.TotalPhysicalMemory/1GB,1);Fecha=(Get-Date -Format 'yyyy-MM-dd HH:mm');Tecnico=$env:USERNAME} | ConvertTo-Html -Fragment -As List
    $b=Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID,@{n='GB';e={[math]::Round($_.Size/1GB)}},@{n='Libre GB';e={[math]::Round($_.FreeSpace/1GB)}} | ConvertTo-Html -Fragment
    $c=Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 10 HotFixID,Description,InstalledOn | ConvertTo-Html -Fragment
    ConvertTo-Html -Title "Reporte $env:COMPUTERNAME" -Body "<h1>Reporte de servicio</h1><h2>Equipo</h2>$a<h2>Discos</h2>$b<h2>Ultimos parches</h2>$c" | Set-Content $f -Encoding UTF8
    Invoke-Item $f; "Reporte guardado en: $f"
}
T 'Taller' 'Abrir carpeta de bitacora' 1 'Cada ejecucion queda registrada con fecha, tecnico, equipo y resultado.' {
    param($InputText,$ApiKey,$Model,$LastOutput)
    New-Item -ItemType Directory -Force 'C:\ProgramData\NavajaSuiza\logs' | Out-Null
    Invoke-Item 'C:\ProgramData\NavajaSuiza\logs'; 'Carpeta abierta.'
}
)

# ---------- Interfaz ----------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Navaja Suiza - Taller TI" Width="1120" Height="760"
        WindowStartupLocation="CenterScreen" Background="#1E1F22" FontFamily="Segoe UI">
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="230"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <DockPanel Grid.Row="0" Margin="0,0,0,8" LastChildFill="True">
      <TextBlock Text="NAVAJA SUIZA" Foreground="White" FontSize="20" FontWeight="Bold" VerticalAlignment="Center" Margin="0,0,16,0"/>
      <Button x:Name="BtnCfg" DockPanel.Dock="Right" Content="API Gemini" Padding="12,4" Margin="8,0,0,0"/>
      <ComboBox x:Name="LevelBox" DockPanel.Dock="Right" Width="130" Margin="8,0,0,0"/>
      <TextBlock Text="Buscar:" Foreground="#9AA0A6" VerticalAlignment="Center" Margin="0,0,6,0"/>
      <TextBox x:Name="Search" FontSize="15" Padding="6" VerticalContentAlignment="Center"/>
    </DockPanel>
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions><ColumnDefinition Width="170"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="CatPanel"/></ScrollViewer>
      <ScrollViewer Grid.Column="1" VerticalScrollBarVisibility="Auto" Margin="8,0,0,0"><WrapPanel x:Name="ToolPanel"/></ScrollViewer>
    </Grid>
    <Grid Grid.Row="2" Margin="0,8,0,4">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <TextBlock Text="Entrada:" Foreground="#9AA0A6" VerticalAlignment="Center" Margin="0,0,6,0"/>
      <TextBox x:Name="InputBox" Grid.Column="1" Padding="5" VerticalContentAlignment="Center" ToolTip="Host, impresora, sintoma o pregunta para la IA"/>
      <Button x:Name="BtnCancel" Grid.Column="2" Content="Cancelar" Padding="10,4" Margin="8,0,0,0"/>
      <Button x:Name="BtnCopy"   Grid.Column="3" Content="Copiar salida" Padding="10,4" Margin="6,0,0,0"/>
      <Button x:Name="BtnClear"  Grid.Column="4" Content="Limpiar" Padding="10,4" Margin="6,0,0,0"/>
    </Grid>
    <TextBox x:Name="OutBox" Grid.Row="3" IsReadOnly="True" FontFamily="Consolas" FontSize="12"
             Background="#111214" Foreground="#D4D4D4" TextWrapping="NoWrap" AcceptsReturn="True"
             VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
    <TextBlock x:Name="Status" Grid.Row="4" Foreground="#9AA0A6" Margin="0,4,0,0" Text="Listo"/>
  </Grid>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
foreach ($n in 'BtnCfg','LevelBox','Search','CatPanel','ToolPanel','InputBox','BtnCancel','BtnCopy','BtnClear','OutBox','Status') {
    Set-Variable -Name $n -Value $win.FindName($n)
}

$bc = New-Object Windows.Media.BrushConverter
$levelColor = @{ 1 = $bc.ConvertFromString('#2E7D32'); 2 = $bc.ConvertFromString('#B26A00'); 3 = $bc.ConvertFromString('#8E2430') }
$script:Cat  = 'Todas'
$script:Job  = $null
$script:Cur  = $null
$script:Buf  = $null
$script:Last = ''

function Add-Out([string]$s) {
    $OutBox.AppendText($s + "`r`n"); $OutBox.ScrollToEnd()
    if ($script:Buf) { [void]$script:Buf.AppendLine($s) }
}

function Write-Log {
    try {
        New-Item -ItemType Directory -Force $logDir | Out-Null
        $f = Join-Path $logDir ((Get-Date -Format 'yyyy-MM-dd') + '.log')
        $hdr = "[{0}] {1}@{2} | {3}" -f (Get-Date -Format 'HH:mm:ss'), $env:USERNAME, $env:COMPUTERNAME, $script:Cur.Name
        Add-Content -Path $f -Value ($hdr + "`r`n" + $script:Buf.ToString()) -Encoding UTF8
    } catch {}
}

function Invoke-Tool($t) {
    if ($script:Job) { Add-Out '[!] Hay una tarea en curso. Espera o pulsa Cancelar.'; return }
    if ($t.Confirm) {
        $r = [Windows.MessageBox]::Show("Ejecutar: $($t.Name)`n`n$($t.Desc)", 'Confirmar', 'YesNo', 'Question')
        if ($r -ne 'Yes') { return }
    }
    $cfg = Get-Cfg; $key = Get-ApiKey
    $script:Cur = $t; $script:Buf = New-Object Text.StringBuilder
    Add-Out ("`r`n=== {0}  ({1}) ===" -f $t.Name, (Get-Date -Format 'HH:mm:ss'))
    $Status.Text = "Ejecutando: $($t.Name) ..."
    $script:Job = Start-Job -ScriptBlock $JobWrapper -ArgumentList $Common, $t.Do.ToString(), $InputBox.Text, $key, $cfg.Model, $script:Last
    $timer.Start()
}

function New-ToolButton($t) {
    $b = New-Object Windows.Controls.Button
    $b.Width = 205; $b.Height = 62; $b.Margin = '4'; $b.Padding = '8,4'
    $b.HorizontalContentAlignment = 'Left'; $b.Foreground = 'White'; $b.BorderThickness = 0; $b.Cursor = 'Hand'
    $b.Background = $levelColor[$t.Level]
    $sp = New-Object Windows.Controls.StackPanel
    $n = New-Object Windows.Controls.TextBlock; $n.Text = $t.Name; $n.FontWeight = 'SemiBold'; $n.TextWrapping = 'Wrap'
    $m = New-Object Windows.Controls.TextBlock; $m.Text = ("N{0} - {1}" -f $t.Level, $t.Category); $m.FontSize = 10; $m.Opacity = 0.8
    [void]$sp.Children.Add($n); [void]$sp.Children.Add($m)
    $b.Content = $sp; $b.ToolTip = $t.Desc; $b.Tag = $t
    $b.Add_Click({ param($s, $e) Invoke-Tool $s.Tag })
    $b
}

function Show-Tools {
    $ToolPanel.Children.Clear()
    $q = $Search.Text.Trim().ToLower(); $lv = $LevelBox.SelectedIndex
    foreach ($t in $Tools) {
        if ($script:Cat -ne 'Todas' -and $t.Category -ne $script:Cat) { continue }
        if ($lv -in 1, 2 -and $t.Level -gt $lv) { continue }
        if ($q -and (($t.Name + ' ' + $t.Desc + ' ' + $t.Category).ToLower() -notlike "*$q*")) { continue }
        [void]$ToolPanel.Children.Add((New-ToolButton $t))
    }
}

function Show-Cats {
    $CatPanel.Children.Clear()
    $cats = @('Todas') + ($Tools | Select-Object -ExpandProperty Category -Unique)
    foreach ($c in $cats) {
        $b = New-Object Windows.Controls.Button
        $b.Content = $c; $b.Margin = '0,0,0,4'; $b.Padding = '8,8'; $b.HorizontalContentAlignment = 'Left'
        $b.Foreground = 'White'; $b.BorderThickness = 0; $b.Tag = $c
        $b.Background = if ($c -eq $script:Cat) { $bc.ConvertFromString('#3A6FF7') } else { $bc.ConvertFromString('#2B2D31') }
        $b.Add_Click({ param($s, $e) $script:Cat = $s.Tag; Show-Cats; Show-Tools })
        [void]$CatPanel.Children.Add($b)
    }
}

# Temporizador que recoge la salida del job sin congelar la ventana
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(400)
$timer.Add_Tick({
    if (-not $script:Job) { $timer.Stop(); return }
    $done = $script:Job.State -ne 'Running'
    foreach ($l in @(Receive-Job $script:Job -ErrorAction SilentlyContinue)) { Add-Out "$l" }
    if ($done) {
        Remove-Job $script:Job -Force; $script:Job = $null; $timer.Stop(); $Status.Text = 'Listo'
        if ($script:Cur.Category -ne 'IA con Gemini') { $script:Last = $script:Buf.ToString() }
        Write-Log; $script:Buf = $null
    }
})

$LevelBox.ItemsSource = @('Todos los niveles', 'Nivel 1', 'Nivel 2', 'Nivel 3'); $LevelBox.SelectedIndex = 0
$Search.Add_TextChanged({ Show-Tools })
$LevelBox.Add_SelectionChanged({ Show-Tools })
$BtnClear.Add_Click({ $OutBox.Clear() })
$BtnCopy.Add_Click({ [Windows.Clipboard]::SetText($OutBox.Text); $Status.Text = 'Salida copiada al portapapeles' })
$BtnCancel.Add_Click({
    if ($script:Job) {
        Stop-Job $script:Job; Remove-Job $script:Job -Force; $script:Job = $null; $timer.Stop()
        Add-Out '[cancelado]'; $Status.Text = 'Cancelado'; $script:Buf = $null
    }
})
$BtnCfg.Add_Click({
    Add-Type -AssemblyName Microsoft.VisualBasic
    $cfg = Get-Cfg
    $k = [Microsoft.VisualBasic.Interaction]::InputBox('Pega tu API key de Gemini (se guarda cifrada para este usuario de Windows). Vacio = no cambiar.', 'API Gemini', '')
    $m = [Microsoft.VisualBasic.Interaction]::InputBox('Modelo de Gemini a usar:', 'API Gemini', $cfg.Model)
    if ($k) { $cfg.Key = ($k | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString) }
    if ($m) { $cfg.Model = $m }
    New-Item -ItemType Directory -Force $cfgDir | Out-Null
    $cfg | ConvertTo-Json | Set-Content $cfgFile -Encoding UTF8
    $Status.Text = 'Configuracion de Gemini guardada'
})

Show-Cats; Show-Tools
Add-Out "Navaja Suiza lista. Equipo: $env:COMPUTERNAME | Admin: $isAdmin"
[void]$win.ShowDialog()
