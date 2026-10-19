# Bitácora — ad-hardened-lab

## 2026-10-19 — Promoción de corp.alegre.internal y línea base

**Estado previo**
- DC01 con Windows Server 2022, adaptadores HostOnly (192.x.x.x) e IntNet (10.x.x.x).
- Conectividad con el manager Wazuh verificada por TCP 1514.
- Snapshot `pre-ad` tomado con la VM apagada.

**Acciones**
1. Instalé el rol AD-DS con `Install-WindowsFeature`. Sin promover todavía.
2. Validé requisitos con `Test-ADDSForestInstallation`, sin cambios en el sistema. Advertencias: cifrado NT4 por defecto (no se modificó) y delegación DNS (no aplica en el lab).
3. Promoví el bosque `corp.alegre.internal` (NetBIOS ALEGRE) con `Install-ADDSForest`, sin `-Force` para leer cada advertencia.
4. Problema: el DNS publicó las dos IPs del DC. Corregido con `RegisterThisConnectionsAddress = False` en el adaptador HostOnly y borrado de los registros A de `192.x.x.x`.
5. Causa del problema con el borrado: un filtro con nombres de propiedad mal escritos (`RecordData`) no devolvía coincidencias y el comando no mostraba error. Solución: `RecordData.IPv4Address.IPAddressToString`.

**Decisiones**
- Un bosque con un solo dominio. Las subredes IP no requieren subdominios; las OUs se usan en la Fase 3.
- Red interna separada (10.x.x.x) del canal de administración y Wazuh (192.x.x.x).
- Reinicios desde Windows con motivo "planificado", para que el log de eventos distinga mantenimiento de caída.

**Línea base**
- Snapshot `baseline-default` tomado con la VM apagada, después de verificar el DNS.
- Pendiente antes de la fase de ataques: `dcdiag /q` sin errores y PingCastle.

**Pendiente**
- Fecha real de instalación de Sysmon (el log dice 08/10, la bitácora 17-18/10).