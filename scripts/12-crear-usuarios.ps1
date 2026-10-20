#Requires -Modules ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$DominioObjetivo,
    [string]$RutaConfig = (Join-Path $PSScriptRoot '..\config\users.json'),
    [string]$OUUsuarios = 'OU=Usuarios,OU=Corp'
)

# Autor: AlegreGonza | 2026-10-20 | Crea usuarios desde config/users.json. Idempotente.
# La contraseña inicial se pide una vez por consola y nunca se guarda en el repo.
# Si algo falla, se borran los usuarios creados en esta corrida. Los existentes no se tocan.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RutaConfig)) {
    throw "No se encuentra la configuración: $RutaConfig. No se creó nada."
}
$filas = (Get-Content -LiteralPath $RutaConfig -Raw -Encoding UTF8 | ConvertFrom-Json).usuarios

$patronUsuario = '^[a-z0-9._-]{3,20}$'
$errores = @()
foreach ($f in $filas) {
    if ($f.usuario -cnotmatch $patronUsuario) { $errores += "Usuario mal formado: $($f.usuario)" }
}
if ($errores.Count -gt 0) {
    throw ("Datos inválidos, no se creó nada:`n" + ($errores -join "`n"))
}

$dominio = Get-ADDomain
if ($dominio.DNSRoot -ne $DominioObjetivo) {
    throw "El DC pertenece a '$($dominio.DNSRoot)', no a '$DominioObjetivo'."
}
$ouDN = "$OUUsuarios,$($dominio.DistinguishedName)"

try {
    Get-ADOrganizationalUnit -Identity $ouDN | Out-Null
}
catch {
    throw "No existe la OU de usuarios: $ouDN. Ejecutá antes el script 10."
}

$gruposFaltantes = $filas | Where-Object { $_.grupo } | Select-Object -ExpandProperty grupo -Unique |
    Where-Object { -not (Get-ADGroup -Filter "SamAccountName -eq '$_'" -ErrorAction SilentlyContinue) }
if ($gruposFaltantes) {
    throw "Grupos inexistentes en AD: $($gruposFaltantes -join ', '). Revisá si hay un error de tipeo en users.json. Si el grupo no existe en AD, corré antes el script 11 (si está en grupos.json)."
}

$passwordInicial = Read-Host -AsSecureString "Contraseña inicial para todos los usuarios nuevos"
$creados = @()
$deshabilitados = @()

try {
    foreach ($f in $filas) {
        $existe = Get-ADUser -Filter "SamAccountName -eq '$($f.usuario)'" -ErrorAction SilentlyContinue
        if ($existe) {
            if ($existe.Enabled) {
                Write-Host "[=] Ya existe: $($f.usuario)"
            }
            else {
                Write-Host "[!] Existe pero está deshabilitado: $($f.usuario)"
                $deshabilitados += $f.usuario
            }
        }
        elseif ($PSCmdlet.ShouldProcess($f.usuario, 'Crear usuario')) {
            $creados += $f.usuario
            New-ADUser -Name "$($f.nombre) $($f.apellido)" -GivenName $f.nombre -Surname $f.apellido `
                -SamAccountName $f.usuario -UserPrincipalName "$($f.usuario)@$($dominio.DNSRoot)" `
                -Path $ouDN -AccountPassword $passwordInicial -Enabled $true -ChangePasswordAtLogon $true
            Write-Host "[+] Creado: $($f.usuario)"
        }

        if ($f.grupo -and $PSCmdlet.ShouldProcess($f.usuario, "Agregar a $($f.grupo)")) {
            $miembros = Get-ADGroupMember -Identity $f.grupo | Select-Object -ExpandProperty SamAccountName
            if ($miembros -notcontains $f.usuario) {
                Add-ADGroupMember -Identity $f.grupo -Members $f.usuario
                Write-Host "[+] Agregado a $($f.grupo): $($f.usuario)"
            }
        }
    }
}
catch {
    Write-Warning "Falló la corrida. Se borran los usuarios creados en esta corrida."
    foreach ($u in $creados) {
        if (Get-ADUser -Filter "SamAccountName -eq '$u'" -ErrorAction SilentlyContinue) {
            Remove-ADUser -Identity $u -Confirm:$false
            Write-Host "[-] Borrado: $u"
        }
    }
    throw
}

if ($deshabilitados.Count -gt 0) {
    Write-Warning "Estos usuarios existen pero están deshabilitados. Revisalos a mano: $($deshabilitados -join ', ')"
}

Get-ADUser -SearchBase $ouDN -SearchScope OneLevel -Filter * |
    Select-Object SamAccountName, Enabled, DistinguishedName | Format-Table -AutoSize
