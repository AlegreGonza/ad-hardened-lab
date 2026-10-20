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

---

## 2026-10-20 — Fase 3 completa: OUs, grupos AGDLP y usuarios

**Acciones**
1. Snapshot `pre-fase3` tomado antes de empezar.
2. Script 10 (OUs): crea `_Administracion` (Tier0, Tier1, Tier2) y `Corp` (Usuarios, Equipos, Servidores, Grupos). Ejecutado en DC01. Segunda corrida: todas las OUs en `Ya existe`, sin duplicados.
3. Script 11 (grupos AGDLP): lee `config/grupos.json` y valida los nombres antes de crear nada. Convención: `G_<Rol>` para globales y `DL_<Recurso>_<Permiso>` para dominio local. Creó 5 grupos. Una segunda corrida con un grupo nuevo en el JSON creó solo el faltante.
4. Script 12 (usuarios): lee `config/users.json`, crea las cuentas en `OU=Usuarios,OU=Corp`, pide la contraseña inicial una vez por consola y agrega cada usuario a su grupo. Si algo falla, borra los usuarios creados en esa corrida. Resultado: 12 cuentas de prueba, 9 con grupo y 3 sin grupo.
5. Repo: `config/ous.json`, `config/grupos.json`, `config/users.json` y los scripts 10, 11 y 12 subidos a `master`.

**Problemas y aprendizajes**
- "Access denied" al crear usuarios: el mensaje era engañoso. La causa real fue la política de contraseñas del dominio, que la contraseña no cumplía. Lo confirmó el error `ADPasswordComplexityException` en el siguiente intento.
- Cuenta parcial: `New-ADUser` crea el objeto antes de validar la contraseña. Si la contraseña falla, queda una cuenta deshabilitada sin contraseña. Se corrigió el script 12 con rollback de la corrida y aviso de cuentas deshabilitadas existentes.
- Sesión sin elevar: `Domain Admins` aparece como `deny only` en una consola sin elevación. Hay que abrir PowerShell con "Ejecutar como administrador".
- Ansible: queda para la tercera repetición (DC02, SRV01, WS01). Los scripts 10 a 12 leen los mismos JSON que va a usar.

**Pendiente**
- Fase 4 (IAM): tomar snapshot `pre-fase4` antes de empezar.
- Script 13: política de contraseñas general y FGPP por grupo, con `-WhatIf`. Va antes de crear usuarios reales.
- Sacar `t0-gonza` de Domain Admins, con cuenta break-glass verificada antes.
- Fase 0: PingCastle sobre `baseline-default`.
- Prueba end-to-end de Sysmon en Wazuh Discover.
