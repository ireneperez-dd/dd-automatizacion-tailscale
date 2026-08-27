#!/usr/bin/env bash
#
# alta-tailscale-macos.sh
# Alta de un Mac de la empresa en el tailnet.
#
# Convencion de nombres: dentaldata-<iniciales>
# Tag: tag:docker-etl
#
# IMPORTANTE: la variante Standalone usa una extension de sistema que macOS
# obliga a aprobar MANUALMENTE la primera vez (Ajustes del Sistema).
# Sin MDM esto NO puede ser 100% desatendido. El script te avisa y espera.
#
# Uso:
#   sudo ./alta-tailscale-macos.sh
#       -> pregunta iniciales y auth key
#
#   sudo ./alta-tailscale-macos.sh -i jm -k tskey-auth-xxxxx
#

set -euo pipefail

INICIALES=""
SUFIJO=""
AUTHKEY="${TS_AUTHKEY:-}"
APITOKEN="${TS_APITOKEN:-}"
TAILNET="-"
TAG="tag:docker-etl"
VERSION=""
PKG_LOCAL=""
SOLO_INSTALAR=0

TS_APP="/Applications/Tailscale.app"
TS_CLI="$TS_APP/Contents/MacOS/Tailscale"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$1"; }
err() { printf '\n  ERROR: %s\n\n' "$1" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--iniciales)   INICIALES="$2"; shift 2 ;;
        -s|--sufijo)      SUFIJO="$2";    shift 2 ;;
        -k|--auth-key)    AUTHKEY="$2";   shift 2 ;;
        -t|--api-token)   APITOKEN="$2";  shift 2 ;;
        -n|--tailnet)     TAILNET="$2";   shift 2 ;;
        -g|--tag)         TAG="$2";       shift 2 ;;
        -v|--version)     VERSION="$2";   shift 2 ;;
        -p|--pkg)         PKG_LOCAL="$2"; shift 2 ;;
        --solo-instalar)  SOLO_INSTALAR=1; shift ;;
        -h|--help)        sed -n '3,25p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) err "Argumento desconocido: $1" ;;
    esac
done

# ------------------------------------------------- 0. Comprobaciones
[[ $EUID -eq 0 ]] || err "Ejecutalo con sudo."

MACOS_VER=$(sw_vers -productVersion | cut -d. -f1)
if [[ "$MACOS_VER" -lt 12 ]]; then
    err "Se necesita macOS Monterey 12.0 o superior (detectado: $(sw_vers -productVersion))."
fi

# El usuario real (no root) para el paso de aprobacion de la extension
USUARIO_REAL=$(stat -f "%Su" /dev/console)

# ------------------------------------------------- 1. Nombre del equipo
while [[ ! "$INICIALES" =~ ^[a-zA-Z]{2,4}$ ]]; do
    echo ""
    echo "  Convencion: dentaldata-<iniciales>   ej. Javier Moreno -> jm"
    read -rp "Iniciales (nombre + apellido, 2-4 letras): " INICIALES
    if [[ ! "$INICIALES" =~ ^[a-zA-Z]{2,4}$ ]]; then
        echo "  Solo letras, entre 2 y 4."
    fi
done

HOSTNAME_TS="dentaldata-$(echo "$INICIALES" | tr '[:upper:]' '[:lower:]')"
if [[ -n "$SUFIJO" ]]; then
    HOSTNAME_TS="${HOSTNAME_TS}-$(echo "$SUFIJO" | tr '[:upper:]' '[:lower:]')"
fi

log "Nombre asignado: $HOSTNAME_TS"

# ------------------------------------------------- 2. Comprobar duplicados
if [[ -z "$APITOKEN" ]]; then
    log "AVISO: sin token de API no compruebo si '$HOSTNAME_TS' ya existe."
    read -rp "Continuar? (s/N) " RESP
    [[ "$RESP" =~ ^[sS]$ ]] || { log "Cancelado."; exit 0; }
else
    log "Comprobando nombres en el tailnet..."
    RESPUESTA=$(curl -fsS -u "${APITOKEN}:" \
        "https://api.tailscale.com/api/v2/tailnet/${TAILNET}/devices" 2>/dev/null || echo "")

    if [[ -z "$RESPUESTA" ]]; then
        log "No he podido consultar la API. Continuo sin comprobar."
    else
        EXISTE=$(printf '%s' "$RESPUESTA" | python3 -c "
import json,sys
d=json.load(sys.stdin).get('devices',[])
n=[x.get('name','').split('.')[0].lower() for x in d]
print('SI' if '$HOSTNAME_TS' in n else 'NO', len(n))
")
        if [[ "${EXISTE%% *}" == "SI" ]]; then
            echo ""
            echo "  '$HOSTNAME_TS' YA EXISTE en el tailnet."
            echo "  Si es una reinstalacion, borra primero el nodo viejo en la consola."
            err "Nombre duplicado."
        fi
        log "Nombre libre (${EXISTE##* } equipos en el tailnet)."
    fi
fi

# ------------------------------------------------- 3. Auth key
if [[ $SOLO_INSTALAR -eq 0 && -z "$AUTHKEY" ]]; then
    echo ""
    echo "  Usa la auth key de EMPRESA (la asociada a $TAG)."
    read -rsp "Pega la auth key: " AUTHKEY
    echo ""
fi

# ------------------------------------------------- 4. Descarga del .pkg
if [[ -n "$PKG_LOCAL" ]]; then
    [[ -f "$PKG_LOCAL" ]] || err "No encuentro el pkg en '$PKG_LOCAL'."
    PKG="$PKG_LOCAL"
    LIMPIAR=0
    log "Usando pkg local: $PKG"
elif [[ -d "$TS_APP" ]]; then
    log "Tailscale ya esta instalado. Salto la descarga."
    PKG=""
    LIMPIAR=0
else
    if [[ -z "$VERSION" ]]; then
        log "Consultando la ultima version estable..."
        VERSION=$(curl -fsSL https://pkgs.tailscale.com/stable/ \
            | grep -oE 'Tailscale-[0-9]+\.[0-9]+\.[0-9]+-macos\.pkg' \
            | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
            | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
        [[ -n "$VERSION" ]] || err "No he podido determinar la version. Usa -v <version> o -p <ruta al pkg>."
    fi
    log "Version a instalar: $VERSION"

    PKG="/tmp/Tailscale-${VERSION}-macos.pkg"
    LIMPIAR=1

    log "Descargando Tailscale ${VERSION}..."
    curl -fsSL -o "$PKG" \
        "https://pkgs.tailscale.com/stable/Tailscale-${VERSION}-macos.pkg" \
        || err "Fallo la descarga. Comprueba la conexion o usa -p con un pkg local."

    TAM=$(stat -f%z "$PKG")
    [[ "$TAM" -gt 5000000 ]] || err "El fichero descargado solo pesa $((TAM/1000000)) MB. Sospechoso."

    # Verificar que la firma del paquete es de Tailscale
    if ! pkgutil --check-signature "$PKG" 2>/dev/null | grep -qi "tailscale"; then
        err "La firma del paquete no es de Tailscale. No lo instalo."
    fi
    log "Paquete verificado ($((TAM/1000000)) MB)."
fi

# ------------------------------------------------- 5. Instalacion
if [[ -n "$PKG" ]]; then
    log "Instalando Tailscale..."
    installer -pkg "$PKG" -target / >/dev/null || err "La instalacion ha fallado."
    [[ "$LIMPIAR" -eq 1 ]] && rm -f "$PKG"
fi

[[ -x "$TS_CLI" ]] || err "No encuentro el CLI en $TS_CLI"

# Enlace en el PATH para poder usar 'tailscale' sin la ruta completa
if [[ ! -e /usr/local/bin/tailscale ]]; then
    mkdir -p /usr/local/bin
    ln -sf "$TS_CLI" /usr/local/bin/tailscale
    log "Creado enlace en /usr/local/bin/tailscale"
fi

# ------------------------------------------------- 6. Extension de sistema
log "Arrancando la aplicacion..."
sudo -u "$USUARIO_REAL" open -a "$TS_APP" || true

echo ""
echo "  ============================================================"
echo "   PASO MANUAL: macOS exige aprobar la extension de sistema."
echo ""
echo "   1. Si aparece una alerta, pulsa 'Abrir Ajustes del Sistema'."
echo "   2. Ve a Ajustes del Sistema > General > Inicio y extensiones"
echo "      (en versiones antiguas: Privacidad y Seguridad)."
echo "   3. Permite la extension de Tailscale."
echo "   4. Acepta tambien la configuracion de VPN si la pide."
echo ""
echo "   Sin este paso el tunel no puede levantarse."
echo "  ============================================================"
echo ""
read -rp "Pulsa Enter cuando lo hayas aprobado... " _

# Esperar a que el demonio responda
log "Esperando a que Tailscale este listo..."
LISTO=0
for _ in $(seq 1 30); do
    if "$TS_CLI" status >/dev/null 2>&1 || "$TS_CLI" status 2>&1 | grep -qi "logged out"; then
        LISTO=1
        break
    fi
    sleep 2
done

[[ "$LISTO" -eq 1 ]] || err "Tailscale no responde. Comprueba que la extension esta aprobada y reintenta."

if [[ $SOLO_INSTALAR -eq 1 ]]; then
    log "Instalado sin dar de alta (--solo-instalar)."
    exit 0
fi

# ------------------------------------------------- 7. Alta en el tailnet
log "Dando de alta '$HOSTNAME_TS' con $TAG ..."

if ! "$TS_CLI" up \
    --auth-key="$AUTHKEY" \
    --hostname="$HOSTNAME_TS" \
    --advertise-tags="$TAG" \
    --accept-dns=true \
    --accept-routes=false; then
    err "'tailscale up' ha fallado. Revisa el tag de la key y los tagOwners."
fi

# ------------------------------------------------- 8. Verificacion
sleep 3

IP=$("$TS_CLI" ip -4 2>/dev/null | head -1 || echo "?")

echo ""
log "ALTA COMPLETADA"
log "  Equipo  : $HOSTNAME_TS"
log "  IP      : $IP"
log "  Tag     : $TAG"
log "  Version : $("$TS_CLI" version | head -1)"
echo ""
log "Comprueba el estado con:  tailscale status"
