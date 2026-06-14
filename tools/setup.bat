@echo off
chcp 65001 >nul 2>&1
echo.
echo ╔══════════════════════════════════════╗
echo ║      Setup Robot 3DOF  (Windows)     ║
echo ╚══════════════════════════════════════╝
echo.

:: ── Verificar Python ─────────────────────────────────────────
where python >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python no encontrado.
    echo         Descargalo desde https://www.python.org
    echo         Asegurate de marcar "Add Python to PATH" al instalarlo.
    pause
    exit /b 1
)

for /f "tokens=*" %%v in ('python --version') do echo [OK] %%v encontrado.

:: ── Instalar dependencias Python ─────────────────────────────
echo.
echo ^>^> Instalando PlatformIO y pyserial...
python -m pip install --upgrade pip --quiet
python -m pip install platformio pyserial --quiet
echo [OK] PlatformIO y pyserial instalados.

:: ── Pre-descargar plataforma ESP32 ───────────────────────────
echo.
echo ^>^> Descargando plataforma ESP32 para PlatformIO (~200 MB, solo la primera vez)...
pio platform install espressif32
echo [OK] Plataforma ESP32 lista.

:: ── Instrucciones finales ─────────────────────────────────────
echo.
echo ╔══════════════════════════════════════╗
echo ║           Setup completo             ║
echo ╚══════════════════════════════════════╝
echo.
echo   Firmware:
echo     Conecta el ESP32 y ejecuta:
echo       pio run --target upload
echo.
echo   GUI MATLAB:
echo     Requiere MATLAB R2021a o superior.
echo     Ejecutar en MATLAB:
echo       RobotController
echo.
pause
