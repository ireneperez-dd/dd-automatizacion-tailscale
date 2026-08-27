# Alta de equipos en Tailscale

Scripts y documentación para dar de alta equipos en el tailnet de la empresa sin necesidad de login interactivo en el navegador.

> ⚠️ **Repositorio privado.** No hacerlo público y **no subir nunca auth keys ni API tokens** — se pasan por parámetro o por variable de entorno. Ver [Seguridad](#seguridad).

---

## Qué resuelve

El alta manual de un equipo requiere instalar el cliente, abrir el navegador, autenticar contra GitHub y configurar las preferencias a mano. Estos scripts lo reducen a un comando: instalan el cliente, registran el equipo con el tag correcto y aplican las políticas de configuración de una sola vez.

---

## Estructura

```
├── README.md                             ← este fichero
│
├── windows/
│   ├── Alta-Tailscale-v3.ps1             ← equipos de empresa
│   └── Alta-Tailscale-Clinica.ps1        ← equipos de clínica
│
├── linux/
│   └── alta-tailscale-linux.sh           ← equipos de empresa
│
├── macos/
│   └── alta-tailscale-macos.sh           ← equipos de empresa
│
├── docs/
│   ├── GUIA-Alta-Tailscale.md            ← usuario final, Windows
│   ├── GUIA-Alta-Tailscale-Linux-macOS.md← usuario final, Linux y Mac
│   └── IT-Preparacion-Tailscale.md       ← INTERNO: preparación y keys
│
└── legacy/
    ├── Alta-Tailscale.ps1                ← v1, requiere MSI en carpeta de red
    └── Alta-Tailscale-v2.ps1             ← v2, sin descarga automática
```

---

## Qué script usar

| Equipo | Script | Tag que aplica |
|---|---|---|
| Portátil o PC de alguien de la empresa (Windows) | `windows/Alta-Tailscale-v3.ps1` | `tag:docker-etl` |
| Portátil o PC de la empresa (Linux/Ubuntu) | `linux/alta-tailscale-linux.sh` | `tag:docker-etl` |
| Portátil o PC de la empresa (macOS) | `macos/alta-tailscale-macos.sh` | `tag:docker-etl` |
| Ordenador en una clínica (Windows) | `windows/Alta-Tailscale-Clinica.ps1` | `tag:clinic-endpoint` |

Los scripts de `legacy/` se mantienen solo como referencia. No usarlos para altas nuevas.

**No existe versión de clínica para Linux/macOS.** Los equipos de clínica son Windows con Gesden. Si algún día hace falta, se parte del script de Linux añadiendo lo que hace la versión de clínica: no aplicar DNS, no aceptar rutas y configurar reinicio automático del servicio.

---

## Uso rápido

Requiere permisos de administrador y la auth key correspondiente al tipo de equipo.

**Windows** (PowerShell como Administrador):
```powershell
Set-ExecutionPolicy -Scope Process -Bypass -Force
.\Alta-Tailscale-v3.ps1
```

**Linux:**
```bash
chmod +x alta-tailscale-linux.sh
sudo ./alta-tailscale-linux.sh
```

**macOS:**
```bash
chmod +x alta-tailscale-macos.sh
sudo ./alta-tailscale-macos.sh
```

Los tres preguntan las iniciales de la persona y la auth key. Para uso desatendido, todo se puede pasar por parámetro:

```powershell
.\Alta-Tailscale-v3.ps1 -Iniciales jm -AuthKey "tskey-auth-..." -Version 1.102.3
```
```bash
sudo ./alta-tailscale-linux.sh -i jm -k "tskey-auth-..."
```

Ejecuta cualquiera de los `.sh` con `-h` para ver todas las opciones.

---

## Requisitos

| Plataforma | Mínimo | Notas |
|---|---|---|
| Windows | 10 / Server 2016 | PowerShell como Administrador |
| Linux | systemd | Necesita `curl`; `python3` opcional (comprobación de duplicados) |
| macOS | Monterey 12.0 | **Requiere un paso manual**, ver abajo |

Todos necesitan salida a internet hacia `pkgs.tailscale.com`. Si la red lo bloquea, hay parámetro para usar un instalador local (`-MsiPath` en Windows, `-p` en macOS).

### macOS no es 100% desatendido

Apple obliga a aprobar la extensión de sistema de Tailscale manualmente en Ajustes del Sistema. El script se detiene, indica dónde pulsar y espera confirmación. Es un clic humano inevitable sin MDM.

Con MDM (Jamf, Intune, Kandji) se puede pre-aprobar la extensión con un perfil de configuración y eliminar ese paso. Merece la pena si el número de Macs crece.

---

## Convención de nombres

- **Empresa:** `dentaldata-<inicial nombre><inicial apellido>` → `dentaldata-jm`
  El script lo construye y valida el formato. Segundo equipo de la misma persona: sufijo explícito (`dentaldata-jm-portatil`).
- **Clínica:** nombre libre, el script solo valida que sea válido para Tailscale.

Hay nombres históricos que no siguen el patrón (`dentaldata-g2`, `dentaldata-xe`, `xema14`). No se renombran, pero las altas nuevas sí lo siguen.

**Reinstalaciones:** borrar primero el nodo antiguo en la consola. Si no, Tailscale crea `<nombre>-1` y se acumulan nodos fantasma.

---

## Qué configuran los scripts

Aplican políticas a nivel de máquina que el usuario no puede modificar desde la interfaz.

| Ajuste | Empresa | Clínica |
|---|---|---|
| Conexión sin sesión de usuario | Sí | Sí |
| Permitir conexiones entrantes | Sí | Sí |
| Menú de preferencias visible | Sí | **No** |
| Aplicar DNS de Tailscale | Sí | **No** |
| Actualizaciones automáticas | — | Sí |
| Reinicio automático del servicio | — | Sí |
| Aceptar rutas de otros nodos | No | No |

El script de clínica no aplica MagicDNS a propósito: esos equipos están en redes que no controlamos y pueden resolver el servidor del PMS por nombre local. Se accede por IP `100.x`. Excepción puntual con `-AceptarDns`.

---

## Seguridad

**Nunca comitear:**
- Auth keys (`tskey-auth-...`)
- API tokens (`tskey-api-...`)
- Ficheros de log de instalación

Las keys se guardan en el gestor de contraseñas de la empresa. Se pasan al script por parámetro o por variable de entorno, nunca escritas dentro del fichero.

`.gitignore` sugerido:

```gitignore
*.log
*.msi
*.pkg
.env
*secret*
*authkey*
*tskey*
```

Una auth key reutilizable de `tag:docker-etl` permite meter cualquier máquina en el tailnet con permisos de conexión hacia todos los equipos de clínica. No es una credencial menor.

Si se filtra una key: revocarla en Settings → Keys y **borrar de Machines** los nodos que no reconozcas. Revocar la key no desconecta los nodos que ya se autenticaron con ella.

---

## Mantenimiento

Las auth keys caducan a los **90 días** como máximo y Tailscale **no avisa**. Se detecta cuando falla un alta.

El calendario de rotación y el procedimiento completo están en `docs/IT-Preparacion-Tailscale.md`.

---

## Documentación

| Para quién | Fichero |
|---|---|
| Quien ejecuta el script en Windows | `docs/GUIA-Alta-Tailscale.md` |
| Quien ejecuta el script en Linux o Mac | `docs/GUIA-Alta-Tailscale-Linux-macOS.md` |
| Quien administra el tailnet | `docs/IT-Preparacion-Tailscale.md` |

Las dos primeras están escritas asumiendo cero conocimientos técnicos y se pueden repartir tal cual. La tercera es interna: contiene el estado real del tailnet y decisiones pendientes.

Antes de repartir las guías de usuario, ajustar en ellas la ruta donde se copian los scripts y a quién dirigirse cuando algo falle.

---

## Pendiente

- [ ] Separar los portátiles de empleados a un tag propio (`tag:empleado`) en vez de reutilizar `docker-etl`. Con un solo tag no se pueden escribir reglas distintas para el ETL y para los portátiles.
- [ ] Restringir las ACLs por puerto hacia `clinic-endpoint` en lugar de `*:*`.
- [ ] Revisar el doble tag de `dentaldata-d` y `dentaldata-host`, que están en ambos lados de la regla de acceso.
- [ ] Fijar una versión de Tailscale común para todas las altas.
- [ ] Revisar los equipos sin *Expiry disabled*: caducan a los 180 días y pueden dejar una máquina inaccesible en remoto.

---

## Referencias

- [Auth keys](https://tailscale.com/docs/features/access-control/auth-keys)
- [Key expiry](https://tailscale.com/docs/features/access-control/key-expiry)
- [MSI properties (Windows)](https://tailscale.com/docs/install/windows/msi)
- [Variantes de macOS](https://tailscale.com/docs/concepts/macos-variants)
- [Referencia del CLI](https://tailscale.com/docs/reference/tailscale-cli)
