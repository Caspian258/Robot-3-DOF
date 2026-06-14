# Robot 3-DOF

Sistema de control para un brazo robótico RRR de 3 grados de libertad, basado en ESP32 con control PD e interfaz gráfica en MATLAB.

## Inicio rápido

> **Requisito previo:** tener [Python 3.8+](https://www.python.org/downloads/) instalado.

**Linux / macOS**
```bash
bash tools/setup.sh
```

**Windows**
```
tools\setup.bat
```

El script instala PlatformIO y pyserial, y pre-descarga la plataforma ESP32 (~200 MB). Después solo necesitas conectar el ESP32 y ejecutar `cd firmware && pio run --target upload`.

---

## Requisitos

| Componente | Versión mínima | Notas |
|---|---|---|
| MATLAB | R2021a | `serialportlist()` requiere R2021a o superior |
| Python | 3.8+ | Solo para el bridge serial en Linux |
| PlatformIO CLI | cualquiera | Recomendado para flashear el firmware |
| Arduino IDE | 2.x | Alternativa a PlatformIO |

---

## Archivos del proyecto

| Archivo | Descripción |
|---|---|
| `firmware/robot3dof_firmware.ino` | Firmware para ESP32 — control PD de 3 motores DC con encoders |
| `firmware/platformio.ini` | Configuración de PlatformIO para ESP32 |
| `matlab/RobotController.m` | GUI de MATLAB — visualización 3D, cinemática inversa, telemetría en tiempo real |
| `tools/robot_serial_bridge.py` | Bridge serial en Python — evita conflictos de lock files en Linux |
| `tools/setup.sh` / `tools/setup.bat` | Scripts de instalación automática (Linux/macOS y Windows) |
| `requirements.txt` | Dependencias Python para el bridge |

---

## Hardware

- **Microcontrolador:** ESP32 DevKit
- **Motores:** 3× JGA25-370 DC con encoder magnético (6 cables)
- **Driver:** L298N (puente H por motor)

### Pines ESP32

| Motor | ENC_A | ENC_B | IN1 | IN2 | ENA |
|---|---|---|---|---|---|
| M1 (Base / yaw) | 18 | 19 | 21 | 22 | 23 |
| M2 (Hombro / pitch) | 32 | 33 | 25 | 26 | 27 |
| M3 (Codo / pitch) | 4 | 5 | 13 | 14 | 16 |

### Parámetros del robot

| Eslabón | Longitud |
|---|---|
| L1 (columna/base) | 100 mm |
| L2 (hombro) | 205 mm |
| L3 (codo/antebrazo) | 165.69 mm |

---

## Setup — Firmware ESP32

### Opción A: PlatformIO (recomendado)

El repositorio ya incluye `firmware/platformio.ini` configurado para la placa `esp32dev`.

1. Instalar Python 3.8+ si no lo tienes.
2. Instalar PlatformIO CLI:
   ```bash
   pip install platformio
   ```
3. Compilar y flashear:
   ```bash
   cd firmware
   pio run --target upload
   ```
   PlatformIO descarga automáticamente el toolchain de Espressif la primera vez.

4. Monitor serial (opcional):
   ```bash
   pio device monitor --baud 115200
   ```

### Opción B: Arduino IDE 2.x

1. Descargar e instalar [Arduino IDE 2.x](https://www.arduino.cc/en/software).
2. Abrir **File → Preferences** y agregar esta URL en "Additional boards manager URLs":
   ```
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   ```
3. Ir a **Tools → Board → Boards Manager**, buscar `esp32` e instalar el paquete de Espressif.
4. Seleccionar **Tools → Board → ESP32 Arduino → ESP32 Dev Module**.
5. Abrir `firmware/robot3dof_firmware.ino`, compilar y subir.

> El firmware no requiere librerías externas — solo el core Arduino para ESP32.

---

## Setup — GUI MATLAB

**Requisito:** MATLAB R2021a o superior (sin toolboxes adicionales).

1. Conectar el ESP32 por USB.
2. Abrir MATLAB, navegar a la carpeta `matlab/` y ejecutar:
   ```matlab
   RobotController
   ```
3. Seleccionar el puerto serial en el desplegable (ej. `COM3` en Windows, `/dev/ttyUSB0` en Linux).
4. Presionar **CONECTAR**.
5. Introducir coordenadas X, Y, Z en mm y presionar **EJECUTAR TRAYECTORIA**.

---

## Setup — Bridge Python (solo Linux, opcional)

Útil cuando MATLAB no puede adquirir el lock del puerto serial en Linux.

```bash
pip install -r requirements.txt
python tools/robot_serial_bridge.py
```

---

## Protocolo Serial (115200 baud)

### MATLAB → ESP32

| Comando | Descripción |
|---|---|
| `T,deg1,deg2,deg3` | Nuevo setpoint en grados para los 3 motores |
| `K1,Kp,Kd` | Ganancias PD del motor 1 |
| `K2,Kp,Kd` | Ganancias PD del motor 2 |
| `K3,Kp,Kd` | Ganancias PD del motor 3 |
| `DB,d1,d2,d3` | Zona muerta por motor (grados) |
| `ZERO` | Resetear encoders y setpoints a cero |
| `DISARM` | Desactivar control, motores en freno |
| `FREE` | Soltar corriente (motores libres) |

### ESP32 → MATLAB

| Respuesta | Descripción |
|---|---|
| `D,q1,q2,q3,e1,e2,e3,pwm1,pwm2,pwm3` | Telemetría: posición actual, error y PWM de los 3 motores |
| `READY` | ESP32 listo tras el boot |
| `ZEROED` | Confirmación de reset de encoders |
| `DISARMED` | Confirmación de desactivación |
| `FREE` | Confirmación de motores libres |
