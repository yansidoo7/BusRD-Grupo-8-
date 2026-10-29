#!/usr/bin/env bash
set -euo pipefail
# Requiere Docker, Python 3 y acceso a Internet. Solo crea una instancia desechable.
# Uso: ./validacion/docker-terminal.sh VIAJE_ID
cd "$(dirname "$0")/.."
: "${1:?Indique el ViajeID. 16400 es solo ejemplo técnico; confirme el asignado.}"
command -v docker >/dev/null
command -v python3 >/dev/null
name="busrd-grupo8-test-$(date +%s)"
port="${BUSRD_PORT:-14338}"
export BUSRD_PASSWORD="$(python3 -c 'import secrets;print(secrets.token_urlsafe(28)+"aA1!")')"
export BUSRD_HOST=127.0.0.1 BUSRD_PORT="$port" BUSRD_USER=sa
cleanup(){ docker rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT
# Contraseña por entorno; no queda grabada en archivos ni en los registros SQL.
export MSSQL_SA_PASSWORD="$BUSRD_PASSWORD"
docker run --detach --name "$name" -e ACCEPT_EULA=Y -e MSSQL_PID=Developer \
 -e MSSQL_SA_PASSWORD -e MSSQL_MEMORY_LIMIT_MB=2048 \
 -p "127.0.0.1:$port:1433" mcr.microsoft.com/mssql/server:2022-latest >/dev/null
python3 -m venv /tmp/busrd-grupo8-venv
/tmp/busrd-grupo8-venv/bin/pip -q install -r validacion/requirements.txt
/tmp/busrd-grupo8-venv/bin/python - <<'PY'
import os
import time
import pytds

for intento in range(60):
    try:
        conexion = pytds.connect(
            os.environ["BUSRD_HOST"],
            port=int(os.environ["BUSRD_PORT"]),
            user=os.environ["BUSRD_USER"],
            password=os.environ["BUSRD_PASSWORD"],
            database="master",
            autocommit=True,
            login_timeout=3,
        )
        conexion.close()
        print("SQL Server acepta conexiones.")
        break
    except pytds.Error:
        time.sleep(2)
    except OSError:
        time.sleep(2)
else:
    raise SystemExit("SQL Server no aceptó la conexión en el plazo esperado.")
PY
/tmp/busrd-grupo8-venv/bin/python validacion/validar.py --recrear-base-pruebas --viaje "$1"
