# Guía para dar de alta un equipo en Tailscale

Esta guía sirve para dos casos:

| Si el equipo es… | Usa este fichero |
|---|---|
| Un portátil o PC de alguien de la empresa | `Alta-Tailscale-v3.ps1` |
| Un ordenador de una clínica | `Alta-Tailscale-Clinica.ps1` |

Elige **uno** de los dos. No ejecutes los dos en el mismo equipo.

---

## Antes de empezar: lo que necesitas tener a mano

**1. Los ficheros del script**
Cópialos a una carpeta fácil de encontrar en el equipo, por ejemplo `C:\Tailscale`.

**2. Una "auth key"**
Es una contraseña larga que empieza por `tskey-auth-`. Te la da la persona responsable de IT.

> ⚠️ **Hay dos keys distintas y no son intercambiables.** Una es para equipos de la empresa y otra para equipos de clínica. Si usas la que no toca, el script fallará al final. Asegúrate de que te dan la correcta para el caso.

**3. Ser administrador del equipo**
Necesitas poder instalar programas. Si el equipo te lo ha dado la empresa y no puedes instalar nada, pide ayuda a IT antes de seguir.

**4. Que el equipo tenga internet**
Cualquier conexión sirve: wifi, cable o compartir datos del móvil.

**5. Windows 10 o superior**
En versiones anteriores no funciona.

---

## Pasos

### Paso 1 — Abrir PowerShell como administrador

1. Pulsa la tecla **Windows**.
2. Escribe `powershell`.
3. En el resultado **Windows PowerShell**, haz **clic derecho**.
4. Elige **Ejecutar como administrador**.
5. Si Windows pregunta si permites cambios, di **Sí**.

Sabrás que lo has hecho bien porque en la parte de arriba de la ventana aparece la palabra **Administrador**.

> Si la ventana no dice "Administrador", ciérrala y repite el paso. Sin eso el script no puede instalar nada.

---

### Paso 2 — Ir a la carpeta de los scripts

Escribe esto y pulsa Enter (cambia la ruta si los guardaste en otro sitio):

```powershell
cd C:\Tailscale
```

Para comprobar que están ahí, escribe:

```powershell
dir
```

Deberías ver los nombres de los ficheros `.ps1` en la lista.

---

### Paso 3 — Permitir que el script se ejecute

Windows bloquea los scripts por defecto. Escribe esto y pulsa Enter:

```powershell
Set-ExecutionPolicy -Scope Process -Bypass -Force
```

No devuelve ningún mensaje. Es normal.

> Esto solo afecta a **esta ventana**. Al cerrarla, Windows vuelve a su configuración normal. No estás desprotegiendo el equipo.

---

### Paso 4 — Ejecutar el script

**Si es un equipo de la empresa:**

```powershell
.\Alta-Tailscale-v3.ps1
```

**Si es un equipo de una clínica:**

```powershell
.\Alta-Tailscale-Clinica.ps1
```

Fíjate en el `.\` del principio. Sin eso da error.

---

### Paso 5 — Responder a las preguntas

El script te va a preguntar dos o tres cosas.

**Pregunta 1 — El nombre del equipo**

- **Equipos de empresa:** te pide las **iniciales** de la persona (nombre y apellido). Por ejemplo, para Javier Moreno escribes `jm`. El script construye el nombre completo (`dentaldata-jm`).
- **Equipos de clínica:** te pide el **nombre completo** que quieres ponerle. Escríbelo entero, por ejemplo `clinica-dd-00179`.

Reglas del nombre: solo letras, números y guiones. Sin espacios, sin acentos, sin puntos.

**Pregunta 2 — Si continuar sin comprobar duplicados**

Verás un aviso y la pregunta `Continuar? (s/N)`. Escribe **`s`** y pulsa Enter.

**Pregunta 3 — La auth key**

Pega la key que te dieron (clic derecho en la ventana para pegar) y pulsa Enter.

> **No verás nada al pegar.** La ventana se queda en blanco a propósito, como cuando escribes una contraseña. Pega y pulsa Enter con confianza.

---

### Paso 6 — Esperar

El script tarda entre **1 y 3 minutos**. Va escribiendo lo que hace. No cierres la ventana ni pulses nada.

Cuando termine verás algo así:

```
[10:24:31] ALTA COMPLETADA
[10:24:31]   Equipo  : dentaldata-jm
[10:24:31]   IP      : 100.87.12.44
[10:24:31]   Tags    : tag:docker-etl
[10:24:31]   Estado  : Running
```

Si ves **ALTA COMPLETADA** y **Estado: Running**, ya está. Puedes cerrar la ventana.

Avisa a IT del nombre y la IP que aparecen, para que confirmen que el equipo se ve desde su lado.

---

## Si algo va mal

### "No se puede cargar el archivo … no está firmado digitalmente"
Te has saltado el **Paso 3**. Vuelve a hacerlo y repite.

### "El término '.\Alta-Tailscale-v3.ps1' no se reconoce"
No estás en la carpeta correcta. Repite el **Paso 2** y comprueba con `dir` que el fichero aparece.

### "Requires -RunAsAdministrator" o "Acceso denegado"
La ventana no está en modo administrador. Ciérrala y repite el **Paso 1**.

### "El fichero descargado no es un MSI valido"
La red está bloqueando la descarga. Suele pasar en wifis de invitados o con portal cautivo. Prueba a compartir datos del móvil, o pide a IT el instalador para usarlo desde una carpeta local.

### "'tailscale up' fallo" con algo sobre *tags* o *invalid key*
Casi seguro que es la key equivocada (la de empresa en un equipo de clínica, o al revés). También puede estar caducada. Pide la key correcta a IT.

### "Nombre duplicado" o "YA EXISTE"
Ese nombre ya está usado por otro equipo. Si estás **reinstalando** un equipo que ya existía, IT tiene que borrar primero el equipo antiguo en la consola de Tailscale. Si es un equipo nuevo, elige otro nombre.

### "requiere reinicio (codigo 3010)"
No es un error. La instalación fue bien. Reinicia el equipo cuando puedas.

### Cualquier otro error
Copia el texto de la ventana y envíalo a IT junto con esta ruta, que contiene el registro detallado:

```
%TEMP%\tailscale-install.log
```

---

## Comprobar que funciona más adelante

Abre PowerShell (no hace falta administrador) y escribe:

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" status
```

Si sale una lista de equipos, está conectado correctamente.

---

## Notas

- **El icono de Tailscale en la bandeja del sistema:** no hace falta tocarlo. En los equipos de clínica las opciones están deliberadamente ocultas para que nadie desconecte el acceso sin querer.
- **La auth key no se queda guardada** en el equipo. Solo se usa para el registro inicial.
- **No hace falta repetir esto nunca** en el mismo equipo. Se conecta solo al arrancar, incluso sin que nadie inicie sesión.
- **La key es una credencial.** No la envíes por WhatsApp ni la dejes escrita en un post-it. Si crees que se ha visto, dilo a IT para que la revoquen.
