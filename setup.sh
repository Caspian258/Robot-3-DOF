#!/usr/bin/env bash
# Setup Robot 3DOF — Linux / macOS
set -e

echo ""
echo "╔══════════════════════════════════════╗"
echo "║      Setup Robot 3DOF  (Linux/Mac)   ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Verificar Python ──────────────────────────────────────────
if command -v python3 &>/dev/null; then
    PY=python3
elif command -v python &>/dev/null; then
    PY=python
else
    echo "[ERROR] Python no encontrado."
    echo "        Instálalo con tu gestor de paquetes:"
    echo "          Ubuntu/Debian:  sudo apt install python3 python3-pip"
    echo "          Fedora:         sudo dnf install python3"
    echo "          macOS:          brew install python3"
    exit 1
fi

PY_VER=$($PY -c "import sys; print(sys.version_info[:2])")
echo "[OK] Python encontrado: $($PY --version)"

# ── Instalar dependencias Python ──────────────────────────────
echo ""
echo ">> Instalando PlatformIO y pyserial..."
$PY -m pip install --upgrade pip --quiet
$PY -m pip install platformio pyserial --quiet
echo "[OK] PlatformIO y pyserial instalados."

# ── Pre-descargar plataforma ESP32 ────────────────────────────
echo ""
echo ">> Descargando plataforma ESP32 para PlatformIO (~200 MB, solo la primera vez)..."
pio platform install espressif32
echo "[OK] Plataforma ESP32 lista."

# ── Instrucciones finales ─────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════╗"
echo "║           Setup completo ✓           ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  Firmware:"
echo "    Conecta el ESP32 y ejecuta:"
echo "      pio run --target upload"
echo ""
echo "  GUI MATLAB:"
echo "    Requiere MATLAB R2021a o superior."
echo "    Ejecutar en MATLAB:"
echo "      RobotController"
echo ""
