#Requires -Modules ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$DominioObjetivo,
    [string]$RutaConfig = (Join-Path $PSScriptRoot '..\config\ous.json')
)

# Autor: AlegreGonza | 2026-10-20 | Crea OUs desde config/ous.json. Idempotente.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RutaConfig)) {
    $RutaConfig = Read-Host "No encuentro la configuración. Ingresá la ruta a ous.json"
}
$cfg = Get-Content -LiteralPath $RutaConfig -Raw -Encoding UTF8 | ConvertFrom-Json
$proteger = [bool]$cfg.protegerContraBorrado

$dominio = Get-ADDomain
if ($dominio.DNSRoot -ne $DominioObjetivo) {
    throw "El DC pertenece a '$($dominio.DNSRoot)', no a '$DominioObjetivo'."
}
$raiz = $dominio.DistinguishedName

function New-OUSiNoExiste {
    param(
        [Parameter(Mandatory)][string]$Nombre,
        [Parameter(Mandatory)][string]$Padre,
        [Parameter(Mandatory)][bool]$Protegida
    )
    $dn = "OU=$Nombre,$Padre"
    try {
        Get-ADOrganizationalUnit -Identity $dn | Out-Null
        Write-Host "[=] Ya existe: $dn"
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        if ($PSCmdlet.ShouldProcess($dn, 'Crear OU')) {
            New-ADOrganizationalUnit -Name $Nombre -Path $Padre -ProtectedFromAccidentalDeletion $Protegida
            Write-Host "[+] Creada: $dn"
        }
    }
    return $dn
}

$admin = New-OUSiNoExiste -Nombre $cfg.ouAdministracion.nombre -Padre $raiz -Protegida $proteger
foreach ($tier in $cfg.ouAdministracion.tiers) {
    New-OUSiNoExiste -Nombre $tier -Padre $admin -Protegida $proteger | Out-Null
}

$corp = New-OUSiNoExiste -Nombre $cfg.ouCorp.nombre -Padre $raiz -Protegida $proteger
foreach ($sub in $cfg.ouCorp.subOUs) {
    New-OUSiNoExiste -Nombre $sub -Padre $corp -Protegida $proteger | Out-Null
}

Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName | Format-Table -AutoSize
