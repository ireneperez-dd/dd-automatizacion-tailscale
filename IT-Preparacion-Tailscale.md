# Tailscale — Preparación y operación (IT)

> **Documento interno.** No se reparte junto con la guía de usuario.
> El usuario final solo recibe `GUIA-Alta-Tailscale.md` y los scripts.

---

## Resumen

| Qué | Cuántas veces | Dónde |
|---|---|---|
| Comprobar `tagOwners` | Una vez (y al añadir tags nuevos) | Access controls |
| Generar auth key de empresa | Una vez cada 90 días | Settings → Keys |
| Generar auth key de clínica | Una vez cada 90 días | Settings → Keys |
| Entregar la key | En cada alta | Ver "Entrega de la key" |
| Verificar el alta | En cada alta | Machines + `tailscale ping` |

Las auth keys **no** son por equipo. Se generan una vez y sirven para todas las altas hasta que caducan.

---

## Parte 1 — Preparación inicial

Se hace una sola vez, antes de la primera alta.

### 1.1 Comprobar los `tagOwners`

Consola → **Access controls**. El policy file debe contener los dos tags con un propietario válido:

```json
"tagOwners": {
  "tag:docker-etl":       ["autogroup:admin"],
  "tag:clinic-endpoint":  ["autogroup:admin"]
}
```

Una auth key autentica la máquina **como el usuario que la generó**. Si ese usuario no es propietario del tag, el registro se rechaza y el error que ve la persona en el equipo es poco descriptivo. Es el fallo que más tiempo hace perder.

### 1.2 Generar la auth key de equipos de empresa

Consola → **Settings → Keys** → *Generate auth key*.

| Campo | Valor |
|---|---|
| Description | `Alta portátiles empresa` |
| Reusable | **Sí** |
| Ephemeral | **No** |
| Pre-approved | Solo si tenéis device approval activado |
| Expiration | 90 días |
| Tags | `tag:docker-etl` |

> ⚠️ **Ephemeral desactivado es crítico.** Un nodo efímero se borra del tailnet al desconectarse. Es lo correcto para contenedores (`gesden-etl-dagster` usa una key así), y lo incorrecto para un portátil: desaparecería de la consola cada vez que se apagara.

El valor completo (`tskey-auth-...`) **se muestra una única vez**. Cópialo antes de cerrar el diálogo.

### 1.3 Generar la auth key de equipos de clínica

Igual que la anterior, cambiando:

| Campo | Valor |
|---|---|
| Description | `Alta equipos clínica` |
| Tags | `tag:clinic-endpoint` |

**Son dos keys separadas a propósito.** Si alguien ejecuta el script de clínica con la key de empresa, `tailscale up` falla porque la key no autoriza ese tag. Ese fallo es la red de seguridad contra equivocarse de script — no lo elimines usando una key con los dos tags.

### 1.4 Guardar las keys

Gestor de contraseñas de la empresa, **una entrada por key**, con nombre claro y la fecha de caducidad anotada en el campo de notas.

Nunca en: un fichero de texto, el propio script, el chat del equipo, correo personal, WhatsApp.

### 1.5 Recordatorio de rotación

Aviso en el calendario para el **día 80** desde la generación.

Tailscale no notifica la caducidad de una auth key. Lo descubres cuando un alta falla, normalmente con alguien esperando delante del equipo.

### 1.6 Preparar el paquete que se reparte

Una carpeta con tres ficheros:

```
Alta-Tailscale-v3.ps1          (equipos de empresa)
Alta-Tailscale-Clinica.ps1     (equipos de clínica)
GUIA-Alta-Tailscale.md         (instrucciones para el usuario)
```

Antes de repartirla, **edita la guía en dos sitios**:
- La ruta donde se van a copiar los scripts (ahora dice `C:\Tailscale`).
- A quién dirigirse cuando algo falle (ahora dice "IT" genérico).

Decisión recomendada: **fijar la versión de Tailscale** en producción. Si no, cada equipo instala la última estable del día y acabas con versiones distintas entre máquinas.

```powershell
.\Alta-Tailscale-v3.ps1 -Version 1.102.3
```

---

## Parte 2 — En cada alta

### 2.1 Qué se entrega

Solo **una cosa**: la auth key que corresponda al tipo de equipo.

Los scripts y la guía ya están en la carpeta. El nombre del equipo lo decide quien ejecuta.

**No se entrega nunca:** el API token, ni las credenciales de la consola de administración.

### 2.2 Entrega de la key

Por orden de preferencia:

1. **Que IT ejecute el script** (en persona o por remoto). La key no sale de sus manos.
2. **Enlace de un solo uso** del gestor de contraseñas, que caduca al abrirse.
3. **Canal interno de la empresa**, borrando el mensaje después.

Nunca por WhatsApp, correo personal, o cualquier canal fuera del control de la empresa.

> **Por qué importa tanto:** una key reutilizable de `docker-etl` permite meter cualquier máquina en el tailnet con permisos de conexión, es decir, acceso a todos los equipos de las clínicas. No es una contraseña de un servicio menor.

### 2.3 Qué decirle a quien ejecuta

Dos frases:
- De qué tipo es la key: **empresa** o **clínica**.
- Que la borre del sitio donde la ha recibido en cuanto termine.

### 2.4 Qué pedir de vuelta

El **nombre** y la **IP `100.x`** que aparecen al final del script.

### 2.5 Verificar el alta (obligatorio)

El script puede decir `ALTA COMPLETADA` y el equipo no ser alcanzable si las ACLs no cubren el caso. Hasta que no compruebes esto, el alta no está cerrada:

1. Consola → **Machines**: el equipo aparece con el nombre esperado y el **tag correcto**.
2. Desde un equipo interno:
   ```powershell
   tailscale ping <nombre-del-equipo>
   ```
3. Para equipos de clínica, comprobar además el puerto que realmente necesita el ETL, no solo el ping.

---

## Parte 3 — Rotación de keys (cada 90 días)

1. Generar las dos keys nuevas con los mismos ajustes (Parte 1.2 y 1.3).
2. Actualizar las entradas del gestor de contraseñas y las fechas.
3. **Revocar las keys viejas** en Settings → Keys.
4. Renovar el recordatorio del calendario.

**Revocar una key no desconecta nada.** Los nodos ya autorizados siguen funcionando; la revocación solo impide altas nuevas. Para desautorizar un equipo hay que **borrarlo desde Machines**.

> No revoques la key **Reusable, Ephemeral** existente. Es la del aprovisionamiento de `gesden-etl-dagster` y romperías el ETL.

---

## Parte 4 — Mantenimiento periódico

### Equipos sin "Expiry disabled"

En **Machines**, los equipos que no muestran el badge *Expiry disabled* se autenticaron por navegador (GitHub) y caducan a los **180 días**.

Riesgo concreto: si es una máquina de acceso remoto y nadie está delante para hacer el login de GitHub, el día que caduque pierdes el acceso sin aviso previo.

Acción: para máquinas de acceso permanente, menú de la derecha → **Disable key expiry**.

Si ya ha caducado, existe **Temporarily extend key** (da 30 minutos de margen), pero es un parche de urgencia.

### Equipos con doble tag

`dentaldata-d` y `dentaldata-host` tienen **los dos tags** (`clinic-endpoint` y `docker-etl`). Eso los coloca en ambos lados de la regla de acceso: pueden alcanzar todos los endpoints de clínica **y** son alcanzables por cualquier equipo con `docker-etl`.

Si son jump hosts intencionados, documéntalo aquí. Si es herencia de una prueba, quítales el tag que no toque.

### Convención de nombres

Los nombres actuales (`dentaldata-g2`, `dentaldata-xe`, `xema14`) muestran colisiones resueltas a mano de formas distintas. Para altas nuevas se usa:

- **Empresa:** `dentaldata-<inicial nombre><inicial apellido>` — el script lo construye y valida.
- **Clínica:** nombre libre, el script solo valida el formato.

Reinstalaciones: **borrar primero el nodo antiguo** en Machines. Si no, Tailscale crea `<nombre>-1` y acumulas nodos fantasma.

---

## Parte 5 — Qué configuran los scripts

Ambos aplican políticas de máquina en `HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Tailscale`, que el usuario no puede cambiar desde la GUI.

| Ajuste | Empresa | Clínica | Por qué |
|---|---|---|---|
| `TS_UNATTENDEDMODE` | always | always | Conexión sin sesión de usuario |
| `TS_ALLOWINCOMINGCONNECTIONS` | always | always | Permite alcanzarlo |
| `TS_PREFERENCESMENU` | visible | **hide** | Que el personal no desconecte el acceso |
| DNS de Tailscale | aplicado | **no aplicado** | No romper la red local de la clínica |
| `TS_INSTALLUPDATES` | — | always | No ir clínica por clínica a mano |
| Recuperación del servicio | — | `sc.exe failure` | No hay nadie que lo reinicie |

El script de clínica no aplica MagicDNS a propósito: el equipo está en una red que no controlamos y puede resolver el servidor del PMS por nombre local. Se accede por IP `100.x` o por FQDN desde nuestro lado. Excepción puntual: `-AceptarDns`.

---

## Enlaces

- Auth keys y API tokens: `https://login.tailscale.com/admin/settings/keys`
- Equipos: `https://login.tailscale.com/admin/machines`
- ACLs: `https://login.tailscale.com/admin/acls`
- Caducidad global: Device management → Key Expiry

---

## Pendiente de decidir

- [ ] ¿Se separan los portátiles de empleados a un tag propio (`tag:empleado`) en vez de reutilizar `docker-etl`? Con un solo tag no se puede escribir una regla distinta para el ETL y para los portátiles.
- [ ] ¿Se restringen las ACLs por puerto hacia `clinic-endpoint`, o se deja `*:*`?
- [ ] ¿Se revisa el doble tag de `dentaldata-d` y `dentaldata-host`?
- [ ] ¿Se fija una versión de Tailscale para todas las altas?
