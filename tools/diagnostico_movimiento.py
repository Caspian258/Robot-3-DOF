#!/usr/bin/env python3
"""
diagnostico_movimiento.py — Robot RRR 3DOF
Prueba sistemática de respuesta por motor con detección de atasco.

Uso: python3 tools/diagnostico_movimiento.py [puerto]
     python3 tools/diagnostico_movimiento.py /dev/ttyUSB0

SEGURIDAD:
  - DISARM automático si se detecta atasco (PWM>100, error>20° durante 2s)
  - DISARM inmediato si se supera límite físico
  - Límites: M1 ±80°, M2 ±45°, M3 ±45°

Protocolo serial esperado:
  TX: T,q1,q2,q3\\n  |  ZERO\\n  |  DISARM\\n
  RX: D,q1,q2,q3,e1,e2,e3,pwm1,pwm2,pwm3\\n
"""

import serial
import serial.tools.list_ports
import time
import sys

# ─── Configuración ────────────────────────────────────────────────────────────
BAUD             = 115200
ESPERA_PRUEBA    = 4.0    # segundos de espera tras cada setpoint
ESPERA_CERO      = 5.0    # segundos para volver a cero entre grupos

# Umbrales de clasificación
OK_ERR        = 5.0    # |error| < 5° → OK
NO_REACT_MAX  = 2.0    # posición < 2° habiendo pedido algo → no reaccionó
OVERSHOOT_MIN = 10.0   # pasó > 10° del objetivo → overshoot

# Modo seguro
STALL_PWM_TH  = 100    # PWM > 100 sospechoso
STALL_ERR_TH  = 20.0   # error > 20° con PWM alto → atasco
STALL_TIME    = 2.0    # segundos de stall antes de DISARM

LIMITES = {0: (-80.0, 80.0), 1: (-45.0, 45.0), 2: (-45.0, 45.0)}
NOMBRES = ['M1 (Base)', 'M2 (Hombro)', 'M3 (Codo)']

SECUENCIAS = [
    (0, [5, 10, 20, 45, 80, -20, -45, -80, 0]),
    (1, [5, 10, 20, 45, -20, -45, 0]),
    (2, [5, 10, 20, 45, -20, -45, 0]),
]

# ─── Resultados acumulados ────────────────────────────────────────────────────
resultados = []   # lista de dicts: motor, pedido, real, error, pwm, diagnostico


# ─── Detección de puerto ──────────────────────────────────────────────────────
def detectar_puerto():
    if len(sys.argv) > 1:
        return sys.argv[1]
    puertos = list(serial.tools.list_ports.comports())
    candidatos = [p.device for p in puertos
                  if 'USB' in p.device or 'ACM' in p.device or 'ttyS' in p.device]
    if not candidatos:
        print('[!] No se encontró ningún puerto serial. Conecta el ESP32.')
        sys.exit(1)
    if len(candidatos) == 1:
        return candidatos[0]
    print('Puertos disponibles:')
    for i, p in enumerate(candidatos):
        print(f'  {i+1}. {p}')
    idx = int(input('Selecciona número de puerto: ')) - 1
    return candidatos[idx]


# ─── Comunicación serial ──────────────────────────────────────────────────────
def leer_frame(ser, timeout=0.15):
    """Lee hasta encontrar una línea D,... Retorna (q[3], e[3], pwm[3]) o None."""
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            line = ser.readline().decode('ascii', errors='ignore').strip()
        except Exception:
            return None
        if line.startswith('D,'):
            partes = line[2:].split(',')
            if len(partes) == 9:
                try:
                    vals = [float(x) for x in partes]
                    q   = vals[0:3]
                    e   = vals[3:6]
                    pwm = [int(vals[6]), int(vals[7]), int(vals[8])]
                    return (q, e, pwm)
                except ValueError:
                    pass
    return None


def enviar(ser, cmd):
    ser.write((cmd + '\n').encode('ascii'))
    ser.flush()


def disarm_emergencia(ser, razon):
    enviar(ser, 'DISARM')
    print(f'\n[!!! EMERGENCIA !!!] {razon} → DISARM enviado')


# ─── Modo seguro durante la espera ───────────────────────────────────────────
def esperar_y_medir(ser, motor_idx, target_deg, duracion=4.0):
    """
    Espera `duracion` segundos leyendo telemetría.
    Retorna (pos_final, error_final, pwm_final, estado)
    estado: None=ok, 'ATASCADO', 'LIMITE_SUPERADO'
    """
    t0          = time.time()
    stall_start = None
    ultimo      = None

    lo, hi = LIMITES[motor_idx]

    while time.time() - t0 < duracion:
        frame = leer_frame(ser, timeout=0.05)
        if frame:
            q, e, pwm = frame
            pos = q[motor_idx]
            err = e[motor_idx]
            p   = pwm[motor_idx]
            ultimo = (pos, err, p)

            # Límite físico superado (con 3° de margen para holgura del encoder)
            if pos < lo - 3.0 or pos > hi + 3.0:
                disarm_emergencia(ser, f'{NOMBRES[motor_idx]} en {pos:.1f}° (límite {lo}°/{hi}°)')
                return ultimo[0], ultimo[1], ultimo[2], 'LIMITE_SUPERADO'

            # Detección de atasco: PWM alto y error grande
            if p > STALL_PWM_TH and abs(err) > STALL_ERR_TH:
                if stall_start is None:
                    stall_start = time.time()
                elif time.time() - stall_start >= STALL_TIME:
                    disarm_emergencia(ser,
                        f'POSIBLE ATASCO — {NOMBRES[motor_idx]}: '
                        f'PWM={p} error={err:.1f}° durante {STALL_TIME:.0f}s')
                    return ultimo[0], ultimo[1], ultimo[2], 'ATASCADO'
            else:
                stall_start = None
        else:
            time.sleep(0.02)

    if ultimo is None:
        return 0.0, target_deg, 0, 'SIN_DATOS'
    return ultimo[0], ultimo[1], ultimo[2], None


# ─── Clasificación ────────────────────────────────────────────────────────────
def clasificar(motor_idx, target, pos, err, pwm, estado_seguro):
    if estado_seguro == 'ATASCADO':
        return '✗ ATASCADO'
    if estado_seguro == 'LIMITE_SUPERADO':
        return '✗ LIMITE SUPERADO'
    if estado_seguro == 'SIN_DATOS':
        return '? SIN DATOS'
    if target == 0:
        if abs(pos) < OK_ERR:
            return '✓ OK (volvió a 0)'
        else:
            return f'⚠ NO VOLVIÓ A CERO ({pos:.1f}°)'
    if abs(pos) < NO_REACT_MAX:
        if abs(target) <= 5.0:
            return f'✗ NO REACCIONÓ (deadband={abs(target)}°≤5°)'
        return '✗ NO REACCIONÓ'
    overshoot = pos - target if target > 0 else target - pos
    if overshoot > OVERSHOOT_MIN:
        return f'⚠ OVERSHOOT (+{overshoot:.1f}°)'
    if abs(err) < OK_ERR:
        return '✓ OK'
    if abs(pos) > NO_REACT_MAX:
        return f'⚠ PARCIAL (llegó a {pos:.1f}°, err={err:.1f}°)'
    return '✗ NO REACCIONÓ'


# ─── Tabla ────────────────────────────────────────────────────────────────────
SEP  = '├─────────────┼────────┼──────────┼──────────┼───────────┼───────────────────────────┤'
HDRR = '│ Motor       │ Pedido │ Real (°) │ Error(°) │ PWM final │ Diagnóstico               │'
TOP  = '┌─────────────┬────────┬──────────┬──────────┬───────────┬───────────────────────────┐'
BOT  = '└─────────────┴────────┴──────────┴──────────┴───────────┴───────────────────────────┘'


def imprimir_fila(nombre, target, pos, err, pwm, diag):
    n   = nombre[:13].ljust(13)
    t   = f'{target:+.0f}°'.ljust(6)
    r   = f'{pos:+.1f}°'.ljust(8)
    e   = f'{err:+.1f}°'.ljust(8)
    p   = str(pwm).ljust(9)
    d   = diag[:25].ljust(25)
    print(f'│ {n} │ {t} │ {r} │ {e} │ {p} │ {d} │')


# ─── Loop principal de prueba ─────────────────────────────────────────────────
def probar_motor(ser, motor_idx, angulos):
    nombre = NOMBRES[motor_idx]
    print(f'\n{"═"*70}')
    print(f'  PRUEBA {nombre}')
    print('═'*70)
    print(TOP)
    print(HDRR)

    abortado = False
    for target in angulos:
        if abortado:
            break

        # Construir setpoint con solo este motor activo
        tq = [0.0, 0.0, 0.0]
        tq[motor_idx] = float(target)
        cmd = f'T,{tq[0]:.2f},{tq[1]:.2f},{tq[2]:.2f}'
        print(SEP)
        print(f'  → Enviando {cmd} (esperando {ESPERA_PRUEBA:.0f}s)...',
              end='\r', flush=True)
        enviar(ser, cmd)

        pos, err, pwm, estado = esperar_y_medir(ser, motor_idx, target, ESPERA_PRUEBA)
        diag = clasificar(motor_idx, target, pos, err, pwm, estado)
        imprimir_fila(nombre, target, pos, err, pwm, diag)

        resultados.append({
            'motor': motor_idx, 'nombre': nombre,
            'target': target, 'pos': pos, 'err': err,
            'pwm': pwm, 'diag': diag,
        })

        if estado in ('ATASCADO', 'LIMITE_SUPERADO'):
            print(f'  [!] Prueba de {nombre} abortada.')
            abortado = True

    print(BOT)

    # Volver a cero al terminar el grupo (si no fue abortado por límite)
    if not abortado or 'LIMITE' not in (resultados[-1]['diag'] if resultados else ''):
        print(f'  → Volviendo a cero... ', end='', flush=True)
        enviar(ser, 'T,0.00,0.00,0.00')
        time.sleep(ESPERA_CERO)
        frame = leer_frame(ser)
        if frame:
            q, *_ = frame
            print(f'OK (pos actual: {q[motor_idx]:.1f}°)')
        else:
            print('(sin confirmación de posición)')


# ─── Resumen y recomendaciones ────────────────────────────────────────────────
def imprimir_resumen():
    print(f'\n{"═"*70}')
    print('  RESUMEN DEL DIAGNÓSTICO')
    print('═'*70)

    for mi in range(3):
        datos = [r for r in resultados if r['motor'] == mi and r['target'] != 0]
        if not datos:
            continue

        nombre = NOMBRES[mi]
        no_react = [r for r in datos if 'NO REACCIONÓ' in r['diag']]
        overshoot = [r for r in datos if 'OVERSHOOT' in r['diag']]
        ok        = [r for r in datos if r['diag'].startswith('✓')]
        atasco    = [r for r in datos if 'ATASCADO' in r['diag']]
        parcial   = [r for r in datos if 'PARCIAL' in r['diag']]

        # Ángulo mínimo que generó movimiento real (|pos| > 2°)
        react_angles = [abs(r['target']) for r in datos
                        if abs(r['pos']) > NO_REACT_MAX and r['target'] != 0]
        min_react = min(react_angles) if react_angles else None

        err_ok = [abs(r['err']) for r in ok]
        err_prom = sum(err_ok) / len(err_ok) if err_ok else None

        print(f'\n  {nombre}:')
        print(f'    Ángulo mínimo con movimiento real : '
              f'{min_react:.0f}°' if min_react else '    Ángulo mínimo con movimiento real : SIN DATOS')
        print(f'    Error promedio (pruebas OK)       : '
              f'{err_prom:.1f}°' if err_prom is not None else '    Error promedio (pruebas OK)       : N/A')
        print(f'    Overshoot                         : {len(overshoot)}/{len(datos)}')
        print(f'    No reaccionó                      : '
              f'{[r["target"] for r in no_react]}')
        if atasco:
            print(f'    *** ATASCADO detectado en targets : '
                  f'{[r["target"] for r in atasco]}')
        if parcial:
            print(f'    Llegada parcial en targets        : '
                  f'{[r["target"] for r in parcial]}')

    # Diagnóstico y recomendaciones
    print(f'\n{"─"*70}')
    print('  DIAGNÓSTICO PROBABLE:')

    deadband_culpable = any(
        r for r in resultados if abs(r['target']) <= 5.0 and 'NO REACCIONÓ' in r['diag']
    )
    overshoot_sys = sum(1 for r in resultados if 'OVERSHOOT' in r['diag']) >= 2

    if deadband_culpable:
        print('  ✗ Deadband de 5° bloquea movimientos pequeños (esperado con config actual)')
        print('    → Reducir deadband a 2° via: DB,2.0,2.0,2.0 desde la GUI')

    if overshoot_sys:
        print('  ⚠ Overshoot sistemático detectado')
        print('    → Aumentar Kd (p.ej. 0.10) o reducir Kp (p.ej. 7.0)')

    no_react_grandes = [r for r in resultados
                        if abs(r['target']) >= 10 and 'NO REACCIONÓ' in r['diag']
                        and 'deadband' not in r['diag']]
    if no_react_grandes:
        print('  ✗ Motor no reacciona ni a ángulos grandes → revisar cableado/driver')
        for r in no_react_grandes:
            print(f'    {r["nombre"]} target={r["target"]}°')

    print(f'\n{"─"*70}')
    print('  PARÁMETROS RECOMENDADOS:')
    db_rec = 2.0 if deadband_culpable else 5.0
    kd_rec = 0.10 if overshoot_sys else 0.05
    kp_rec = 7.0 if overshoot_sys else 10.0
    print(f'    Deadband : {db_rec}°  (actual 5.0°)')
    print(f'    Kp       : {kp_rec}  (actual 10.0)')
    print(f'    Kd       : {kd_rec}  (actual 0.05)')
    print(f'    → Enviar desde GUI: DB,{db_rec},{db_rec},{db_rec}')
    print('═'*70)


# ─── Entrada principal ────────────────────────────────────────────────────────
def main():
    puerto = detectar_puerto()
    print(f'Conectando a {puerto} @ {BAUD} baud...')

    try:
        ser = serial.Serial(puerto, BAUD, timeout=0.3)
    except serial.SerialException as e:
        print(f'[!] No se pudo abrir {puerto}: {e}')
        sys.exit(1)

    time.sleep(2.0)  # esperar boot del ESP32
    ser.reset_input_buffer()

    # Esperar READY o continuar si ya está corriendo
    print('Esperando ESP32...', end='', flush=True)
    t0 = time.time()
    while time.time() - t0 < 3.0:
        line = ser.readline().decode('ascii', errors='ignore').strip()
        if 'READY' in line:
            break
        time.sleep(0.05)
    print(' listo.')

    # ZERO inicial
    print('\nEnviando ZERO para fijar referencia...')
    enviar(ser, 'ZERO')
    t0 = time.time()
    while time.time() - t0 < 4.0:
        line = ser.readline().decode('ascii', errors='ignore').strip()
        if 'ZEROED' in line:
            print('  ZEROED recibido.')
            break
        time.sleep(0.05)
    time.sleep(0.5)

    print('\n[AVISO] Iniciando secuencia de pruebas de movimiento.')
    print('        Asegúrate de que el robot tiene espacio libre en todos los ejes.')
    print('        Presiona Ctrl+C en cualquier momento para DISARM inmediato.\n')
    input('        Presiona ENTER para comenzar...')

    try:
        for motor_idx, angulos in SECUENCIAS:
            probar_motor(ser, motor_idx, angulos)

        imprimir_resumen()

    except KeyboardInterrupt:
        print('\n\n[!] Interrupción manual — enviando DISARM')
        enviar(ser, 'DISARM')

    finally:
        enviar(ser, 'DISARM')
        ser.close()
        print('\nConexión cerrada. Revisión completa.')


if __name__ == '__main__':
    main()
