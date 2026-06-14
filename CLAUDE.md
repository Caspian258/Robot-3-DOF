# CLAUDE.md — Robot 3-DOF (Control MATLAB + ESP32)

> Leído al inicio de cada sesión. Actualizar junto con BITACORA.md cuando
> algo importante cambie.

---

## Contexto del proyecto

Brazo robótico RRR de 3 grados de libertad construido como reto escolar
("Diseño y simulación de una estación de trabajo robotizada en una celda de
manufactura industrial"). El sistema completo corre **sin ROS2**: el ESP32
ejecuta control PD local y se comunica por USB-Serial con una GUI en MATLAB.

---

## Stack

| Capa | Tecnología | Notas |
|---|---|---|
| Firmware | PlatformIO + Arduino framework | `firmware/robot3dof_firmware.ino` |
| Microcontrolador | ESP32 DevKit | USB-Serial 115200 baud |
| GUI / IK | MATLAB `matlab/RobotController.m` | uifigure, uiaxes 3D |
| Bridge serial (Linux) | `tools/robot_serial_bridge.py` | evita lock-file de MATLAB en `/run/lock` |

---

## Hardware — pines VERIFICADOS FÍSICAMENTE

```
         ENC_A  ENC_B   IN1   IN2   ENA
Motor 1:   18     19     21    22    23   ← Base (yaw)
Motor 2:   32     33     25    26    27   ← Hombro (pitch)
Motor 3:    4      5     13    14    16   ← Codo (pitch)
```

> Lógica: bloques consecutivos sin conflicto con encoders ni pines input-only (34/35/36/39).
> M3 usa pines 4 y 5 para encoder (tienen pull-up interno, a diferencia de 34/35 que son input-only).

> **Motores:** JGA25-370 con encoder magnético de 6 cables.
> Solo M1 está físicamente conectado al comenzar el proyecto.

> ⚠️  Los pines del README.md público y del firmware deben coincidir siempre
> con esta tabla. Si se cambia un pin físico, actualizar las tres fuentes.

---

## Parámetros geométricos

| Eslabón | Símbolo | Valor |
|---|---|---|
| Columna / base | L1 | 100 mm |
| Hombro | L2 | 205 mm |
| Codo / antebrazo | L3 | 165.69 mm |

---

## Protocolo serial (115200 baud)

### MATLAB → ESP32

| Comando | Descripción | Referencia firmware |
|---|---|---|
| `T,q1,q2,q3\n` | Nuevo setpoint en grados (offset desde cero del encoder) | `procesarSerial()` L233 |
| `K1,Kp,Kd\n` / `K2,` / `K3,` | Ganancias PD por motor | L245 |
| `DB,d1,d2,d3\n` | Zona muerta en grados por motor | L255 |
| `ZERO\n` | Reset encoders, targets a 0, motores en freno | L264 |
| `DISARM\n` | Desactivar control, motores en freno | L276 |
| `FREE\n` | Soltar corriente (motores giran libres, sin freno) | L283 |

### ESP32 → MATLAB

| Respuesta | Descripción |
|---|---|
| `D,q1,q2,q3,e1,e2,e3,pwm1,pwm2,pwm3\n` | Telemetría: posición, error y PWM (9 valores, ~100 Hz) |
| `READY\n` | ESP32 listo tras el boot |
| `ZEROED\n` | Confirmación de ZERO |
| `DISARMED\n` | Confirmación de DISARM |
| `FREE\n` | Confirmación de FREE |

> El firmware NO implementa los comandos legacy `SP:`, `POS:`, `KP:`, `KD:`, `RST`, `STOP`.
> La GUI envía setpoints como ángulos **relativos al cero del encoder** (`q_firmware = q_físico - home_q`).

---

## Parámetros de control

```
Kp  = 10.0  (por motor, ajustable desde GUI)
Kd  = 0.05  (por motor, ajustable desde GUI)
deadband    = 5.0°  (por motor, zona muerta para estado HOLDING)
min_pwm     = 20 cerca de deadband, 35 fuera  (anti-stiction)
COUNTS/REV  = 1200  (⚠️ pendiente verificación física: 6 pulsos × relación × 4×)
LOOP_HZ     = ~100 Hz  (delay(10) en el loop — control + telemetría juntos)
```

> COUNTS/REV: el valor en firmware es 1200 (`PULSOS_POR_VUELTA`). La doc anterior decía 994.
> Verificar físicamente: enviar `T,360,0,0` con M1 y confirmar que gira exactamente 1 vuelta.

---

## Cinemática inversa (analítica — modelo paralelogramo)

```
θ1       = atan2(y, x)
r        = sqrt(x² + y²)
z_rel    = z − L1
D        = (r² + z_rel² − L2² − L3²) / (2·L2·L3)   — clampear a [−1, 1]
θ3_rel   = atan2(−sqrt(1−D²), D)                     — codo hacia abajo
θ2       = atan2(z_rel, r) − atan2(L3·sin(θ3_rel), L2 + L3·cos(θ3_rel))
θ3_motor = θ2 + θ3_rel − π/2                         — ángulo absoluto del motor M3
```

Implementada en `ikRobot()` (matlab/RobotController.m L904).
FK inversa: `r = L2·cos(θ2) + L3·cos(θ3_motor + π/2)`, `z = L1 + L2·sin(θ2) + L3·sin(θ3_motor + π/2)`

> `ikRobot()` valida si D_raw ∈ [-1,1] y muestra advertencia en el log si el target está fuera del workspace.

---

## Estructura del repositorio

```
3DOF/
├── CLAUDE.md                        ← este archivo (contexto para IA)
├── BITACORA.md                      ← registro de avances por sesión
├── README.md                        ← documentación pública
├── .gitignore                       ← excluye firmware/.pio/, .vscode/, robot_log.csv
├── requirements.txt                 ← pyserial>=3.5
├── firmware/
│   ├── robot3dof_firmware.ino       ← firmware ESP32 (PlatformIO / Arduino IDE)
│   └── platformio.ini               ← src_dir=. apunta al mismo directorio
├── matlab/
│   └── RobotController.m            ← GUI MATLAB principal
├── tools/
│   ├── robot_serial_bridge.py       ← bridge serial para Linux (workaround lock file)
│   ├── setup.sh                     ← instalación Linux/macOS
│   └── setup.bat                    ← instalación Windows
├── docs/                            ← documentación adicional (vacía por ahora)
└── CAD/                             ← archivos SolidWorks (SLDPRT, SLDASM)
```

---

## Reglas para Claude Code

1. **Nunca agregarte como coautor** en commits de GitHub.
2. **Leer este archivo al inicio** de cada sesión antes de tocar código.
3. **Buscar reutilizable antes de crear**: si ya existe algo similar,
   extenderlo en vez de duplicar.
4. **Actualizar `BITACORA.md`** al final de cada tarea importante con:
   - Fecha
   - Qué se hizo y por qué
   - Estado actual
   - Próximos pasos
5. Los pines del firmware **siempre** deben coincidir con la tabla de
   "Pines verificados" de este archivo.
6. El firmware (`firmware/robot3dof_firmware.ino`) **no se toca** salvo corrección
   explícita de pines o bugs confirmados. Compilar siempre desde `firmware/` (`cd firmware && pio run`).
7. Commits descriptivos en **español**.
8. Un paso a la vez — mostrar resultado antes de continuar con el siguiente.

---

## Contexto del reto escolar

El proyecto responde al reto *"Diseño y simulación de una estación de trabajo
robotizada en una celda de manufactura industrial"*. Las tres etapas evaluadas
son:

1. **Investigación y Diseño** — estado del arte, componentes, estrategia de
   control, sustentabilidad.
2. **Construcción y Experimentación** — integración sensores/actuadores,
   comunicación, lazos de control, programación.
3. **Análisis y Presentación** — validación, demostración de objetivos,
   conclusiones, reflexión ética.

Tener este contexto en mente al generar documentación, comentarios de código
o respuestas para el reporte.
