# Bitácora — ad-hardened-lab

Registro cronológico del proyecto. Cada entrada incluye acciones, decisiones y pendientes. No se registran contraseñas, claves ni datos del host.

---

## 2026-10-19 — Promoción de corp.alegre.internal y línea base

**Estado previo**
- DC01 con Windows Server 2022, adaptadores HostOnly (192.x.x.x) e IntNet (10.x.x.x).
- Conectividad con el manager Wazuh verificada por TCP 1514.
- Snapshot `pre-ad` tomado con la VM apagada.

**Acciones**
1. Instalé el rol AD-DS con `Install-WindowsFeature`, sin promover todavía.
2. Validé requisitos con `Test-ADDSForestInstallation`, sin cambios en el sistema. Advertencias: cifrado NT4 por defecto (no se modificó) y delegación DNS (no aplica en el lab).
3. Promoví el bosque `corp.alegre.internal` (NetBIOS ALEGRE) con `Install-ADDSForest`, sin `-Force` para leer cada advertencia.
4. Problema: el DNS publicó las dos IPs del DC. Corregido con `RegisterThisConnectionsAddress = False` en el adaptador HostOnly y borrado de los registros A de `192.x.x.x`.
5. Causa del problema con el borrado: un filtro con nombres de propiedad mal escritos (`RecordData`) no devolvía coincidencias y el comando no mostraba error. Solución: `RecordData.IPv4Address.IPAddressToString`.
6. `dcdiag` con pruebas de servicios, replicación y publicidad: pasaron. Los eventos de error recientes corresponden a apagados sin cierre limpio, no a fallas del dominio.

**Decisiones**
- Un bosque con un solo dominio. Las subredes IP no requieren subdominios; las OUs se usan en la Fase 3.
- Red interna separada (10.x.x.x) del canal de administración y Wazuh (192.x.x.x).
- Reinicios desde Windows con motivo "planificado", para que el log de eventos distinga mantenimiento de caída.

**Línea base**
- Snapshot `baseline-default` tomado con la VM apagada, después de verificar el DNS.

**Pendiente**
- Fecha real de instalación de Sysmon (el log dice 08/10, la bitácora 17-18/10).

---

## 2026-10-19 — Cuenta de administración diaria y break-glass

**Acciones**
1. Creé `t0-gonza` como cuenta de administración diaria. La contraseña se ingresó por prompt seguro.
2. Primer intento de creación con la contraseña escrita dentro del comando. Lo detecté, eliminé la cuenta y la recreé con el prompt. Lección: nunca pasar contraseñas como parámetro en comandos ni scripts.
3. Inicio de sesión con `t0-gonza` y cambio de contraseña obligatorio en el primer ingreso.
4. Cambié la contraseña de `Administrator` para dejarla como cuenta de emergencia (break-glass). Desde `t0-gonza` el cambio fue rechazado por permisos, lo que confirma que la cuenta diaria no puede modificar la de emergencia. El cambio se hizo desde la sesión de `Administrator`.

**Decisiones**
- Administración diaria solo con `t0-gonza`. `Administrator` queda para emergencias, con su contraseña guardada fuera de la VM.

**Verificación**
- `whoami` devuelve la cuenta `t0-gonza` del dominio.
- `Get-ADGroupMember` muestra `t0-gonza` y `Administrator` en Domain Admins.

**Desvío del plan**
- `t0-gonza` quedó en Domain Admins para poder trabajar. El plan pide que Domain Admins tenga solo la cuenta break-glass.
- Corrección pendiente: crear un grupo Tier 0 delegado y sacar a `t0-gonza` de Domain Admins, en la Fase 4 y con snapshot previo.

**Línea base**
- `baseline-default`: AD recién promovido, sin cuentas propias.
- `t0-gonza-creada`: estado con la cuenta diaria y la break-glass cambiada.

**Pendiente**
- Fase 3: OUs y grupos AGDLP.
- Fase 4: Fine-Grained Password Policy, Protected Users, LAPS y corrección del desvío de Domain Admins.