#Requires -Modules ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$DominioObjetivo,
    [string]$RutaConfig = (Join-Path $PSScriptRoot '..\config\grupos.json')
)

# Autor: AlegreGonza | 2026-10-20 | Crea grupos AGDLP desde config/grupos.json. Idempotente.
# Convención de nombres:
#   G_<Rol>                 grupos globales (quién): G_Soporte_Nivel1
#   DL_<Recurso>_<Permiso>  grupos de dominio local (qué puede hacer): DL_FS01_Lectura
# Si algún nombre no cumple la convención, el script se detiene antes de crear nada.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RutaConfig)) {
    throw "No se encuentra la configuración: $RutaConfig. No se creó nada."
}
$cfg = Get-Content -LiteralPath $RutaConfig -Raw -Encoding UTF8 | ConvertFrom-Json
$proteger = [bool]$cfg.protegerContraBorrado

$patronGlobal = '^G_[A-Za-z0-9]+(_[A-Za-z0-9]+)*$'
$patronDL     = '^DL_[A-Za-z0-9]+_[A-Za-z0-9]+$'

$errores = @()
foreach ($g in $cfg.gruposGlobales) {
    if ($g.nombre -notmatch $patronGlobal) { $errores += "Grupo global mal nombrado: $($g.nombre)" }
}
foreach ($g in $cfg.gruposDominioLocal) {
    if ($g.nombre -notmatch $patronDL) { $errores += "Grupo de dominio local mal nombrado: $($g.nombre)" }
}
if ($errores.Count -gt 0) {
    throw ("Nombres inválidos, no se creó nada:`n" + ($errores -join "`n"))
}

$dominio = Get-ADDomain
if ($dominio.DNSRoot -ne $DominioObjetivo) {
    throw "El DC pertenece a '$($dominio.DNSRoot)', no a '$DominioObjetivo'."
}
$ouDN = "$($cfg.ouDestino),$($dominio.DistinguishedName)"

try {
    Get-ADOrganizationalUnit -Identity $ouDN | Out-Null
}
catch {
    throw "No existe la OU destino: $ouDN. Ejecutá antes el script 10."
}

function New-GrupoSiNoExiste {
    param(
        [Parameter(Mandatory)][string]$Nombre,
        [Parameter(Mandatory)][string]$Descripcion,
        [Parameter(Mandatory)][ValidateSet('Global', 'DomainLocal')][string]$Alcance,
        [Parameter(Mandatory)][string]$Ruta,
        [Parameter(Mandatory)][bool]$Protegido
    )
    $dn = "CN=$Nombre,$Ruta"
    try {
        Get-ADGroup -Identity $dn | Out-Null
        Write-Host "[=] Ya existe, no se modifica: $dn"
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        if ($PSCmdlet.ShouldProcess($dn, "Crear grupo $Alcance")) {
            New-ADGroup -Name $Nombre -SamAccountName $Nombre -DisplayName $Nombre `
                -Description $Descripcion -GroupScope $Alcance -GroupCategory Security `
                -Path $Ruta
            Set-ADObject -Identity $dn -ProtectedFromAccidentalDeletion $Protegido
            Write-Host "[+] Creado: $dn"
        }
    }
}

foreach ($g in $cfg.gruposGlobales) {
    New-GrupoSiNoExiste -Nombre $g.nombre -Descripcion $g.descripcion -Alcance 'Global' -Ruta $ouDN -Protegido $proteger
}
foreach ($g in $cfg.gruposDominioLocal) {
    New-GrupoSiNoExiste -Nombre $g.nombre -Descripcion $g.descripcion -Alcance 'DomainLocal' -Ruta $ouDN -Protegido $proteger
}

Get-ADGroup -SearchBase $ouDN -SearchScope OneLevel -Filter * |
    Select-Object Name, GroupScope, DistinguishedName | Format-Table -AutoSize
