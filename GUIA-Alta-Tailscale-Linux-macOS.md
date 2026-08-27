# Guía para dar de alta un equipo en Tailscale — Linux y macOS

Elige el apartado según tu equipo:

- **[Linux / Ubuntu](#linux--ubuntu)** → script `alta-tailscale-linux.sh`
- **[macOS](#macos)** → script `alta-tailscale-macos.sh`

*(Si el equipo es Windows, usa la otra guía: `GUIA-Alta-Tailscale.md`)*

---

## Antes de empezar

**1. El fichero del script**
Cópialo a tu carpeta personal, por ejemplo `~/Descargas` o `~/tailscale`.

**2. Una "auth key"**
Es una contraseña larga que empieza por `tskey-auth-`. Te la da la persona responsable de IT. Pídele **la de equipos de empresa**.

**3. Poder usar `sudo`**
Necesitas ser administrador del equipo. Si no puedes instalar programas, habla con IT antes de seguir.

**4. Conexión a internet**
Cualquiera sirve: wifi, cable o datos compartidos del móvil.

**5. Tus iniciales**
El script te las va a pedir: inicial del nombre + inicial del apellido. Por ejemplo, Javier Moreno → `jm`. Con eso construye el nombre del equipo (`dentaldata-jm`).

---

# Linux / Ubuntu

### Paso 1 — Abrir la terminal

Pulsa `Ctrl` + `Alt` + `T`.

### Paso 2 — Ir a la carpeta del script

Escribe esto y pulsa Enter (ajusta la carpeta si lo guardaste en otro sitio):

```bash
cd ~/Descargas
```

Para comprobar que el fichero está ahí:

```bash
ls alta-tailscale-linux.sh
```

Si responde con el nombre del fichero, vas bien. Si dice *No such file or directory*, no estás en la carpeta correcta.

### Paso 3 — Dar permiso de ejecución

```bash
chmod +x alta-tailscale-linux.sh
```

No devuelve ningún mensaje. Es normal. Solo hace falta hacerlo una vez.

### Paso 4 — Ejecutar el script

```bash
sudo ./alta-tailscale-linux.sh
```

Te pedirá **tu contraseña del equipo** (la de tu usuario, no la auth key). Al escribirla no se ve nada: es normal en Linux. Escribe y pulsa Enter.

> Fíjate en el `./` del principio. Sin eso da error.

### Paso 5 — Responder a las preguntas

**Pregunta 1 — Tus iniciales.** Escribe por ejemplo `jm` y pulsa Enter.

**Pregunta 2 — `Continuar? (s/N)`.** Escribe `s` y pulsa Enter.

**Pregunta 3 — La auth key.** Pega la key (`Ctrl`+`Shift`+`V` en la terminal) y pulsa Enter.

> **No verás nada al pegar.** Está oculta a propósito, como una contraseña. Pega y pulsa Enter con confianza.

### Paso 6 — Esperar

Tarda entre 1 y 3 minutos. Cuando acabe verás:

```
[10:24:31] ALTA COMPLETADA
[10:24:31]   Equipo  : dentaldata-jm
[10:24:31]   IP      : 100.87.12.44
[10:24:31]   Tag     : tag:docker-etl
```

Si ves **ALTA COMPLETADA**, ya está. Avisa a IT del nombre y la IP.

---

# macOS

> ⚠️ **En Mac hay un paso manual.** Apple obliga a aprobar la extensión de Tailscale a mano en Ajustes del Sistema. El script se detiene, te dice exactamente dónde pulsar y espera. No es un error: es cómo funciona macOS.

### Paso 1 — Abrir el Terminal

Pulsa `Cmd` + `Espacio`, escribe `terminal` y pulsa Enter.

### Paso 2 — Ir a la carpeta del script

```bash
cd ~/Downloads
```

Para comprobar que está ahí:

```bash
ls alta-tailscale-macos.sh
```

### Paso 3 — Dar permiso de ejecución

```bash
chmod +x alta-tailscale-macos.sh
```

### Paso 4 — Ejecutar el script

```bash
sudo ./alta-tailscale-macos.sh
```

Te pedirá **tu contraseña del Mac** (no la auth key). Al escribirla no se ve nada: es normal.

> Si macOS dice que el fichero *no se puede abrir porque proviene de un desarrollador no identificado*, ejecuta esto una vez y vuelve a intentarlo:
> ```bash
> xattr -d com.apple.quarantine alta-tailscale-macos.sh
> ```

### Paso 5 — Responder a las preguntas

Igual que en Linux: iniciales, luego `s`, luego pega la auth key (`Cmd`+`V`, no se verá nada).

### Paso 6 — Aprobar la extensión de Tailscale

El script se va a parar y mostrar un aviso enmarcado. Cuando llegue ahí:

1. Se abrirá la app de Tailscale y probablemente una alerta del sistema.
2. Ve a **Ajustes del Sistema → General → Inicio y extensiones**.
   *(En macOS más antiguo: **Privacidad y Seguridad**, abajo del todo.)*
3. Busca la extensión de **Tailscale** y **permítela**. Te pedirá tu contraseña.
4. Si aparece un aviso de **configuración de VPN**, acéptalo también.

Cuando lo hayas hecho, vuelve al Terminal y pulsa **Enter**.

> Si no encuentras dónde aprobarla, no sigas a ciegas: llama a IT y comparte pantalla. Es más rápido que buscarlo.

### Paso 7 — Esperar

El script continúa solo y termina con el mismo mensaje de **ALTA COMPLETADA**. Avisa a IT del nombre y la IP.

---

# Si algo va mal

### `Permission denied` al ejecutar
Te has saltado el `chmod +x` (Paso 3).

### `command not found` o `No such file or directory`
No estás en la carpeta correcta, o falta el `./` delante del nombre. Comprueba con `ls`.

### `Ejecutalo con sudo`
Has olvidado `sudo` al principio del comando.

### `Falta 'curl'` (solo Linux)
Instálalo y reintenta:
```bash
sudo apt install curl
```

### `Este script asume systemd` (solo Linux)
Tu distribución no usa systemd. Pásalo a IT: hay que arrancar el servicio de otra forma.

### `Se necesita macOS Monterey 12.0 o superior`
El Mac es demasiado antiguo para la versión actual de Tailscale. Habla con IT.

### `La firma del paquete no es de Tailscale` (solo macOS)
La descarga se ha corrompido o la red la está interceptando. Suele pasar en wifis de invitados con portal cautivo. Prueba compartiendo datos del móvil.

### `Fallo la descarga` / `No he podido determinar la version`
Sin internet o la red bloquea la descarga. Prueba otra conexión, o pide a IT el instalador para usarlo desde un fichero local.

### `'tailscale up' ha fallado`
Casi siempre es la auth key: equivocada, caducada, o es la de clínica en vez de la de empresa. Pide a IT la correcta.

### `Nombre duplicado` / `YA EXISTE`
Otro equipo usa ya ese nombre. Si estás **reinstalando**, IT tiene que borrar primero el equipo antiguo en la consola. Si no, prueba con tres iniciales (nombre + dos apellidos) o pide un sufijo a IT.

### `Tailscale no responde` (solo macOS)
La extensión no está aprobada. Vuelve al Paso 6 y revísalo.

### Cualquier otro error
Copia el texto de la terminal y envíalo a IT. Para Linux, añade también la salida de:
```bash
sudo journalctl -u tailscaled -n 50
```

---

# Comprobar que funciona más adelante

En cualquier momento, sin `sudo`:

```bash
tailscale status
```

Si sale una lista de equipos, está conectado correctamente.

---

# Notas

- **No hace falta repetir esto nunca** en el mismo equipo. Se conecta solo al arrancar.
- **La auth key no se guarda** en el equipo. Solo se usa para el registro inicial.
- **Borra la key** del sitio donde la recibiste (chat, correo) cuando termines.
- **La key es una credencial de la empresa.** No la reenvíes a nadie ni la dejes escrita. Si crees que se ha visto, dilo a IT para que la revoquen.
- **Truco para no dejar la key en el historial:** en lugar de pegarla cuando la pida, puedes lanzarlo así:
  ```bash
  sudo TS_AUTHKEY='tskey-auth-xxxxx' -E ./alta-tailscale-linux.sh -i jm
  ```
  Es opcional; el método normal es igual de válido.
