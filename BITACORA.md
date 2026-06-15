# BITACORA.md — Robot RRR 3-DOF

Registro de avances por sesión de trabajo. Orden cronológico descendente (más reciente arriba).

---

## 2026-06-14 — Panel izquierdo dos columnas + script de verificación completa

### Qué se hizo y por qué

**Problema 1 — Fix definitivo del scroll del panel izquierdo:**

El `uipanel` con `Scrollable='on'` dentro de un `uigridlayout` no genera scroll en MATLAB/Linux: el grid layout toma control del tamaño del panel y clipa el contenido sin desplazarlo (bug de interacción entre uipanel scrollable y uigridlayout como padre).

Solución: panel izquierdo dividido en **dos columnas** con `uigridlayout [1,2]` sin scroll:
- Columna L (16 filas, ~504px): DESTINO · SECUENCIA · GANANCIAS PD · ZONA MUERTA
- Columna R (20 filas, ~724px): CONTROL MANUAL · TEST MOTORES · CONEXIÓN · CERO · FK · LOG
- Ambas columnas caben en los ~968px disponibles sin necesitar scroll.

**Problema 2 — Script de verificación completa `tools/verificacion_sistema.py`:**

Diagnóstico de 7 pasos ejecutable sin MATLAB. Uso: `python3 tools/verificacion_sistema.py /dev/ttyUSB0`

| Paso | Qué verifica |
|---|---|
| 1 | Comunicación serial (20 tramas, frecuencia real, formato D,) |
| 2 | Estabilidad de encoders en reposo (deriva < 1°, ruido por trama) |
| 3 | Respuesta por motor: 10°/25°/-10°/-25°/0° con tabla de tiempo de respuesta, error SS y overshoot |
| 4 | Límites por software (enviar > 80°/45° → verificar LIMIT:Mn) |
| 5 | Revisión estática del código anti-atasco en firmware (sin prueba física) |
| 6 | Movimiento combinado 3 motores: T,20,20,20 → T,-20,-20,-20 → ZERO |
| 7 | Semáforo 🟢/🟡/🔴 con recomendaciones de ajuste PD |

Seguridad: DISARM inmediato si FAULT o error > 30° por > 3s. Siempre termina con ZERO.

### Estado actual

| Componente | Estado |
|---|---|
| Panel izquierdo GUI | ✅ Dos columnas — todo el contenido visible sin scroll |
| Script verificacion_sistema.py | ✅ Listo — pendiente ejecutar con robot físico |

### Próximos pasos

1. **Ejecutar verificacion_sistema.py** con robot físico conectado y confirmar pasos 1-7
2. **Verificar animación 3D** — en posición cero el brazo debe mostrar la "L invertida"
3. **Subir firmware** con nuevos parámetros PD (`pio run --target upload`)

---

## 2026-06-14 — Revisión control PD, corrección visual M2/M3 y mejoras GUI

### Qué se hizo y por qué

**Fase 2A — MATLAB (`matlab/RobotController.m`):**

| Cambio | Motivo |
|---|---|
| Negar `current_q(2/3)` antes de sumar `home_q` en `leerTelemetria()` y `leerUnFrame()` | La convención del encoder de M2/M3 es opuesta a la cinemática: el encoder lee negativo cuando el motor va físicamente positivo (corrección INVERTIDO es eléctrica, no invierte ISR) |
| Negar `q_fw(2/3)` en `moverRobot()` antes de enviar `T,` | Para que IK→firmware sea coherente con la misma convención |
| Negar `fw_target1/2(2/3)` en `runSequence()` | Para que `esperarPosicionMulti()` compare contra el valor de encoder que el firmware realmente alcanzará |
| Parsear `FAULT:` y `LIMIT:` en `leerTelemetria()` y mostrar en LOG | Antes se descartaban silenciosamente; ahora aparecen como `[!] FAULT:M1 — motor bloqueado` |
| Buffer CSV: acumular 50 tramas antes de escribir a disco | Elimina `fopen/fclose` 100×/s → reduce carga de I/O |

**Fase 2B — Firmware (`firmware/robot3dof_firmware.ino`):**

| Cambio | Valor anterior | Valor nuevo | Motivo |
|---|---|---|---|
| Kp | 10.0 | 6.0 | Reduce overshoot con errores grandes (Kp=10 → PWM saturado a 255 inmediato) |
| Kd | 0.05 | 0.08 | Mayor amortiguación para compensar Kp reducido |
| Filtro derivativo | sin filtro | α=0.7 (`d_f = 0.7*d_prev + 0.3*d_raw`) | Elimina picos derivativos al cambiar setpoint bruscamente |
| Rate limiter | sin rate limit | 1°/ciclo si salto >30° | Previene saturación de PWM al inicio de movimientos grandes; arranca desde `current_q` |

El rate limiter cancela el estado `holding` mientras la rampa avanza, para que el motor siga activamente la rampa sin necesitar esperar a superar `1.5×deadband`.

### Estado actual

| Componente | Estado |
|---|---|
| Animación 3D M2/M3 | ✅ Corregida — convención de encoder M2/M3 compensada en visualización |
| IK→firmware M2/M3 | ✅ Corregido — setpoints negados para encoder invertido |
| FAULT/LIMIT en GUI | ✅ Visibles en LOG de la GUI |
| CSV buffering | ✅ Escribe cada 50 tramas en vez de cada frame |
| Control PD | ✅ Kp=6 / Kd=0.08 / filtro derivativo α=0.7 / rate limiter 1°/ciclo |

### Próximos pasos

1. **Verificar con robot físico** — enviar T,0,20,0 y confirmar que M2 va a +20° físicos
2. **Tuning fino** si Kp=6 resulta muy lento: considerar subir a 7-8 para M1 (más inercia)
3. **Verificar animación** — en posición cero el brazo debe mostrar la "L invertida" (home=[0,90,-90])

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
