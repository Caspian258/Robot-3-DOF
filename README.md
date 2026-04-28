# Robot 3-DOF

Sistema de control para un brazo robótico RRR de 3 grados de libertad, basado en ESP32 con control PD y interfaz gráfica en MATLAB.

## Componentes

| Archivo | Descripción |
|---|---|
| `robot3dof_firmware.ino` | Firmware para ESP32 — control PD de 3 motores DC con encoders |
| `RobotController.m` | GUI de MATLAB — visualización 3D, cinemática inversa, telemetría en tiempo real |
| `robot_serial_bridge.py` | Bridge serial en Python — evita conflictos de lock files en Linux |

## Hardware

- **Microcontrolador:** ESP32
- **Motores:** 3× DC con encoder (994 counts/rev)
- **Driver:** puente H por motor

### Pines ESP32

| Motor | ENC_A | ENC_B | IN1 | IN2 | ENA |
|---|---|---|---|---|---|
| M1 (Base) | 18 | 19 | 25 | 26 | 27 |
| M2 (Hombro) | 32 | 33 | 21 | 22 | 23 |
| M3 (Codo) | 34 | 35 | 13 | 14 | 16 |

## Protocolo Serial (115200 baud)

| Comando | Descripción |
|---|---|
| `SP:deg1,deg2,deg3` | Setpoint en grados para los 3 motores |
| `KP:valor` | Actualizar ganancia proporcional global |
| `KD:valor` | Actualizar ganancia derivativa global |
| `RST` | Resetear encoders y setpoints a cero |
| `STOP` | Congelar posición actual |

**Respuesta del ESP32:** `POS:deg1,deg2,deg3,sp1,sp2,sp3`

## Parámetros del robot

- **L1** (base): 100 mm  
- **L2** (hombro): 205 mm  
- **L3** (codo): 165.69 mm  

## Uso

### Firmware

1. Abrir `robot3dof_firmware.ino` en Arduino IDE con soporte para ESP32.
2. Verificar los pines según la tabla anterior.
3. Compilar y subir al ESP32.

### GUI MATLAB

1. Conectar el ESP32 por USB.
2. Ejecutar `RobotController.m` en MATLAB.
3. Seleccionar el puerto COM/tty en el desplegable y presionar **CONECTAR**.
4. Introducir coordenadas X, Y, Z en mm y presionar **EJECUTAR TRAYECTORIA**.

### Bridge Python (Linux)

```bash
pip install pyserial
python robot_serial_bridge.py
```

Útil cuando MATLAB no puede adquirir el lock del puerto serial en Linux.
