#!/usr/bin/env bash
#
# alta-tailscale.sh
# Alta de un equipo Linux de la empresa en el tailnet.
#
# Convencion de nombres: dentaldata-<iniciales>
# Tag: tag:docker-etl
#
# Uso:
#   sudo ./alta-tailscale.sh
#       -> pregunta iniciales y auth key
#
#   sudo ./alta-tailscale.sh -i jm -k tskey-auth-xxxxx
#       -> sin preguntas
#
#   sudo TS_AUTHKEY=tskey-auth-xxxxx ./alta-tailscale.sh -i jm
#       -> la key por variable de entorno (no queda en el historial)
#

set -euo pipefail

INICIALES=""
SUFIJO=""
AUTHKEY="${TS_AUTHKEY:-}"
APITOKEN="${TS_APITOKEN:-}"
TAILNET="-"
TAG="tag:docker-etl"
SOLO_INSTALAR=0

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$1"; }
err() { printf '\n  ERROR: %s\n\n' "$1" >&2; exit 1; }

uso() {
    sed -n '3,20p' "$0" | sed 's/^# \?//'
    exit 0
}

# ------------------------------------------------- Argumentos
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--iniciales)   INICIALES="$2"; shift 2 ;;
        -s|--sufijo)      SUFIJO="$2";    shift 2 ;;
        -k|--auth-key)    AUTHKEY="$2";   shift 2 ;;
        -t|--api-token)   APITOKEN="$2";  shift 2 ;;
        -n|--tailnet)     TAILNET="$2";   shift 2 ;;
        -g|--tag)         TAG="$2";       shift 2 ;;
        --solo-instalar)  SOLO_INSTALAR=1; shift ;;
        -h|--help)        uso ;;
        *) err "Argumento desconocido: $1" ;;
    esac
done

# ------------------------------------------------- 0. Comprobaciones
[[ $EUID -eq 0 ]] || err "Ejecutalo con sudo."

command -v curl >/dev/null 2>&1 || err "Falta 'curl'. Instalalo: apt install curl"

if ! command -v systemctl >/dev/null 2>&1; then
    err "Este script asume systemd. En otros init hay que arrancar tailscaled a mano."
fi

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
    elif command -v python3 >/dev/null 2>&1; then
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
            echo "  Si no, usa -s <sufijo> o unas iniciales mas largas."
            err "Nombre duplicado."
        fi
        log "Nombre libre (${EXISTE##* } equipos en el tailnet)."
    else
        log "Sin python3 no puedo parsear la respuesta. Continuo."
    fi
fi

# ------------------------------------------------- 3. Auth key
if [[ $SOLO_INSTALAR -eq 0 && -z "$AUTHKEY" ]]; then
    echo ""
    echo "  Usa la auth key de EMPRESA (la asociada a $TAG)."
    read -rsp "Pega la auth key: " AUTHKEY
    echo ""
fi

# ------------------------------------------------- 4. Instalacion
if command -v tailscale >/dev/null 2>&1; then
    log "Tailscale ya esta instalado ($(tailscale version | head -1))."
else
    log "Instalando Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
fi

log "Habilitando el servicio tailscaled..."
systemctl enable --now tailscaled

# Esperar a que el demonio responda
log "Esperando a que tailscaled este listo..."
for _ in $(seq 1 30); do
    if tailscale status >/dev/null 2>&1 || tailscale status 2>&1 | grep -q "Logged out"; then
        break
    fi
    sleep 1
done

if ! systemctl is-active --quiet tailscaled; then
    err "tailscaled no esta activo. Revisa: journalctl -u tailscaled -n 50"
fi

if [[ $SOLO_INSTALAR -eq 1 ]]; then
    log "Instalado sin dar de alta (--solo-instalar)."
    exit 0
fi

# ------------------------------------------------- 5. Alta en el tailnet
log "Dando de alta '$HOSTNAME_TS' con $TAG ..."

if ! tailscale up \
    --auth-key="$AUTHKEY" \
    --hostname="$HOSTNAME_TS" \
    --advertise-tags="$TAG" \
    --accept-dns=true \
    --accept-routes=false; then
    err "'tailscale up' ha fallado. Revisa el tag de la key y los tagOwners."
fi

# ------------------------------------------------- 6. Verificacion
sleep 3

IP=$(tailscale ip -4 2>/dev/null | head -1 || echo "?")
NOMBRE=$(tailscale status --json 2>/dev/null | grep -o '"HostName":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "$HOSTNAME_TS")

echo ""
log "ALTA COMPLETADA"
log "  Equipo  : $NOMBRE"
log "  IP      : $IP"
log "  Tag     : $TAG"
log "  Version : $(tailscale version | head -1)"
echo ""
log "Comprueba el estado en cualquier momento con:  tailscale status"
