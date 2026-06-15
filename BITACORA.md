# BITACORA.md — Robot RRR 3-DOF

Registro de avances por sesión de trabajo. Orden cronológico descendente (más reciente arriba).

---

## 2026-06-14 — Diagnóstico completo + protección anti-atasco + control por teclado

### Qué se hizo y por qué

**Diagnóstico físico con `tools/diagnostico_movimiento.py`:**

Hallazgos críticos encontrados al correr la secuencia de pruebas:

| Motor | Resultado | Causa |
|---|---|---|
| M1 (Base) | Converge lentamente (~85-90% en 4s) | Kp=10 bajo para la inercia del sistema |
| M2 (Hombro) | **Dirección INVERTIDA** — corrió a -49.6° al pedir +10° | Wiring: encoder/motor en convención opuesta |
| M3 (Codo) | **Dirección INVERTIDA + atasco** — PWM=255 en posición incorrecta | Igual que M2, chocó contra tope mecánico |

**Fase 3 — Firmware (`firmware/robot3dof_firmware.ino`):**
- `INVERTIDO[3] = {false, true, true}`: corrige dirección de M2 y M3 via XOR en la lógica de dirección (sin tocar hardware ni ISRs)
- Límites por software `LIMIT_NEG/LIMIT_POS`: clampea setpoints a ±80°/±45°/±45°, responde `LIMIT:M{n}` si se supera
- Anti-atasco: PWM>150 y encoder quieto (<5 counts) durante 500ms → `FAULT:M{n}`, motor apagado hasta ZERO o DISARM
- Deadband reducida de 5° a 2° (commit anterior): ángulo mínimo funcional ~3°
- GUI default de deadband actualizado de 5° a 2° para consistencia

**Fase 4 — MATLAB (`matlab/RobotController.m`):**
- Panel "CONTROL MANUAL (teclado)" en la GUI
- `fig.KeyPressFcn` → `teclasRobot()`: A/D=M1, W/S=M2, Q/E=M3 (±5°/tecla), Espacio=DISARM, R=ZERO
- Respeta límites ±80°/±45°/±45° antes de enviar comando
- Loguea cada acción en el panel LOG

### Estado actual

| Componente | Estado |
|---|---|
| M1 (Base) | ✅ Dirección correcta — converge, algo lento |
| M2 (Hombro) | ✅ Dirección corregida por software (INVERTIDO[1]=true) |
| M3 (Codo) | ✅ Dirección corregida por software (INVERTIDO[2]=true) |
| Anti-atasco | ✅ Implementado — FAULT:M{n} si 500ms sin movimiento con PWM>150 |
| Límites software | ✅ Implementados — LIMIT:M{n} si setpoint supera topes |
| Control teclado | ✅ A/D/W/S/Q/E + Espacio + R en la GUI MATLAB |
| PULSOS_POR_VUELTA | ⚠️ 1960 (teórico) — pendiente verificación M1 con nueva dirección de M2/M3 |

### Próximos pasos

1. **Verificar M2 y M3** con la nueva dirección — enviar T,0,20,0 y T,0,0,20
2. **Tuning Kp M1** — considerar subir de 10 a 15-20 si sigue convergiendo lento
3. **Verificar PULSOS_POR_VUELTA** — confirmar 1 vuelta exacta en los 3 motores
4. **Probar control por teclado** con robot físico conectado

---

## 2026-06-14 — Corrección de PULSOS_POR_VUELTA (verificación física)

### Qué se hizo y por qué

Corregida la constante `PULSOS_POR_VUELTA` en `firmware/robot3dof_firmware.ino` de **1200** a **1960**.

- **Evidencia física:** con el valor 1200, al enviar `T,360,0,0` el motor M1 giraba solo ~220° en lugar de 360°.
- **Cálculo teórico:** JGA25-370 con encoder de 6 cables (~7 PPR) × 4× (decodificación de cuadratura) × reducción 70:1 ≈ **1960 counts/rev**.
- Actualizados `CLAUDE.md` (parámetros de control y nota de verificación) para reflejar el valor correcto.

### Estado actual

| Componente | Estado |
|---|---|
| `PULSOS_POR_VUELTA` | ✅ Corregido a 1960 (verificación física M1) |

### Próximos pasos

1. **Verificar en físico** — con el nuevo valor enviar `T,360,0,0` y confirmar 1 vuelta exacta
2. **Probar robot_serial_bridge.py** en Linux como alternativa permanente al lock file
3. **Conectar M2 y M3** — verificar dirección de giro y pines

---

## 2026-06-14 — Reorganización de estructura de carpetas

### Qué se hizo y por qué

Reorganización del repositorio para separar responsabilidades por directorio:

| Movimiento | Origen → Destino |
|---|---|
| Firmware | `robot3dof_firmware.ino`, `platformio.ini` → `firmware/` |
| GUI MATLAB | `RobotController.m` → `matlab/` |
| Herramientas | `robot_serial_bridge.py`, `setup.sh`, `setup.bat` → `tools/` |
| Docs | `docs/` creada (vacía con `.gitkeep`) |

Todos los movimientos se hicieron con `git mv` para preservar el historial de cada archivo.
Compilación verificada: `cd firmware && pio run` → `[SUCCESS]` 21.5% Flash, 6.8% RAM.
README.md, CLAUDE.md y BITACORA.md actualizados con las nuevas rutas.

### Estado actual

Igual que sesión anterior — solo cambió la estructura de carpetas, no el código.

### Próximos pasos

1. **Verificar PULSOS_POR_VUELTA** — conectar M1, enviar `T,360,0,0`, confirmar 1 vuelta exacta
2. **Probar `tools/robot_serial_bridge.py`** en Linux como alternativa al lock file de MATLAB
3. **Conectar M2 y M3** — verificar dirección de giro y pines con testMotores()
4. **Tuning PD** — ajustar Kp/Kd y deadband por motor con el robot físico

---

## 2026-06-14 — Auditoría, limpieza de repo y correcciones técnicas

### Qué se hizo y por qué

**Diagnóstico de conexión MATLAB↔ESP32 (Linux):**
- Causa identificada: `/run/lock` tiene permisos `0755 root:root` — MATLAB no puede crear lock files
- Python/pyserial sí funciona (no usa lock files). El ESP32 responde correctamente tramas `D,`
- Fix temporal: `sudo chmod 1777 /run/lock`
- Fix permanente: crear `robot_serial_bridge.py` (pendiente) y configurar tmpfiles.d

**Auditoría completa del proyecto:**
- Protocolo serial: 100% sincronizado entre firmware y GUI (T,/D, es el protocolo real)
- Pines: verificados — los tres archivos (firmware, CLAUDE.md, README) coinciden
- Inconsistencia crítica encontrada: `PULSOS_POR_VUELTA` en firmware = 1200, docs = 994
- `.vscode/` y 255 archivos de proyecto anterior estaban tracked en git

**Limpieza del repo (commit a66c6a9):**
- Eliminados del índice: `Implementacion ROS/` (proyecto ROS2 distinto) y `Validaciones numericas/`
- Untrackeado: `.vscode/` (auto-generado por PlatformIO; ya estaba en .gitignore)
- `git status` queda limpio

**Actualización CLAUDE.md (commit b4cd67a):**
- Protocolo corregido: eliminados SP:/POS:/RST/KP:/KD: (no existen en firmware)
- Parámetros reales: Kp=10.0, Kd=0.05, min_pwm=20/35, LOOP_HZ=~100
- COUNTS/REV marcado como pendiente de verificación física (firmware=1200, docs=994)
- Cinemática: agregado θ3_motor = θ2 + θ3_rel - π/2 y advertencia de workspace
- Estructura del repo actualizada al estado real

**Correcciones técnicas aplicadas:**
- ISR race condition: protegido `encCount` con `portMUX_TYPE` en firmware
- `platformio.ini`: agregado `monitor_filters = esp32_exception_decoder`
- GUI MATLAB: agregado botón "Refresh ports" en dropdown serial
- GUI MATLAB: agregada validación de workspace en `ikRobot()` con advertencia al usuario
- Creado `robot_serial_bridge.py`: bridge Python para evitar lock file de MATLAB en Linux

### Estado actual

| Componente | Estado |
|---|---|
| Firmware ESP32 | ✅ Compila y flashea. Control PD + HOLDING funcional |
| GUI MATLAB | ✅ Funcional con mejoras (refresh ports, validación IK) |
| Comunicación serial | ✅ Verificada con Python — ESP32 responde correctamente |
| M1 (Base) | ✅ Conectado físicamente |
| M2 (Hombro) | ⚠️ Cableado sin verificar en movimiento |
| M3 (Codo) | ⚠️ Cableado sin verificar en movimiento |
| PULSOS_POR_VUELTA | ⚠️ Firmware usa 1200, pendiente verificación física |
| Lock file Linux | ⚠️ Requiere `sudo chmod 1777 /run/lock` o robot_serial_bridge.py |

### Próximos pasos

1. **Verificar PULSOS_POR_VUELTA** — conectar M1, enviar `T,360,0,0`, confirmar 1 vuelta exacta
2. **Probar robot_serial_bridge.py** en Linux como alternativa permanente al lock file
3. **Conectar M2 y M3** — verificar dirección de giro y pines con testMotores()
4. **Tuning PD** — ajustar Kp/Kd y deadband por motor con el robot físico
5. **Validación de workspace** — probar con coordenadas reales del reto escolar

---

## Sesiones anteriores

*(Registro no disponible — esta bitácora se inicia el 2026-06-14)*
