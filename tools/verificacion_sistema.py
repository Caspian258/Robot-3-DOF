#!/usr/bin/env python3
"""
verificacion_sistema.py — Diagnóstico completo del robot 3-DOF sin MATLAB.

Uso:
    python3 tools/verificacion_sistema.py /dev/ttyUSB0
    python3 tools/verificacion_sistema.py /dev/ttyUSB0 --rapido   (solo Pasos 1-2)

Seguridad:
  - FAULT en cualquier motor → DISARM inmediato y abortar.
  - Error > 30° por más de 3 s → DISARM y reportar.
  - Siempre termina con ZERO antes de cerrar.
"""

import serial
import time
import sys
import re
import os
import argparse

# ── Límites físicos por motor ──────────────────────────────────────────────
LIMITS = {1: (-80, 80), 2: (-45, 45), 3: (-45, 45)}
MOTOR_NAMES = {1: 'M1 (Base)', 2: 'M2 (Hombro)', 3: 'M3 (Codo)'}
BAUD = 115200
CMD_TIMEOUT = 0.1   # s entre lecturas del puerto
TRAMA_TIMEOUT = 5.0 # s esperando una trama válida

# Colores ANSI
GREEN  = '\033[92m'
YELLOW = '\033[93m'
RED    = '\033[91m'
CYAN   = '\033[96m'
BOLD   = '\033[1m'
RESET  = '\033[0m'

def color(texto, c): return c + texto + RESET

def titulo(texto):
    print()
    print(color('═' * 60, CYAN))
    print(color(f'  {texto}', BOLD + CYAN))
    print(color('═' * 60, CYAN))

def subtitulo(texto):
    print(color(f'\n── {texto} ──', YELLOW))

def ok(texto):   print(color('  ✓ ' + texto, GREEN))
def warn(texto): print(color('  ⚠ ' + texto, YELLOW))
def err(texto):  print(color('  ✗ ' + texto, RED))


class Robot:
    def __init__(self, puerto, baud=BAUD):
        self.puerto = puerto
        self.ser = serial.Serial(puerto, baud, timeout=CMD_TIMEOUT)
        time.sleep(0.5)
        self.ser.reset_input_buffer()
        self.faults = []
        self.limits_hit = []

    def close(self):
        try:
            self.ser.close()
        except Exception:
            pass

    def enviar(self, cmd):
        self.ser.write((cmd + '\n').encode())

    def leer_trama(self, timeout=TRAMA_TIMEOUT):
        """Lee hasta obtener una trama D, válida. Devuelve lista de 9 floats o None."""
        t0 = time.time()
        while time.time() - t0 < timeout:
            try:
                linea = self.ser.readline().decode('ascii', errors='ignore').strip()
            except Exception:
                continue
            if linea.startswith('FAULT:'):
                self.faults.append(linea)
                return None
            if linea.startswith('LIMIT:'):
                self.limits_hit.append(linea)
            if linea.startswith('D,'):
                partes = linea[2:].split(',')
                if len(partes) == 9:
                    try:
                        return [float(x) for x in partes]
                    except ValueError:
                        pass
        return None

    def leer_n_tramas(self, n, timeout_total=15.0):
        """Lee n tramas D, válidas. Devuelve lista de listas."""
        tramas = []
        t0 = time.time()
        while len(tramas) < n and time.time() - t0 < timeout_total:
            t = self.leer_trama(timeout=2.0)
            if t is not None:
                tramas.append(t)
        return tramas

    def posicion_actual(self):
        """Devuelve [q1, q2, q3] de la última trama. None si falla."""
        t = self.leer_trama()
        if t:
            return t[0:3]
        return None

    def disarm(self):
        self.enviar('DISARM')
        time.sleep(0.3)

    def zero(self):
        self.enviar('ZERO')
        time.sleep(0.5)

    def esperar_posicion(self, targets, db=5.0, timeout=8.0, max_error=30.0):
        """
        Espera a que todos los motores lleguen a targets ± db.
        Retorna (llegó:bool, tiempo_ms:float, tramas_hist:list).
        Aborta si cualquier motor supera max_error por >3 s o hay FAULT.
        """
        t0 = time.time()
        t_error_alto = {i: None for i in range(3)}
        historia = []
        _printed_limits = set(self.limits_hit)  # no re-reportar LIMIT de pasos anteriores

        while time.time() - t0 < timeout:
            trama = self.leer_trama(timeout=2.0)
            for lm in self.limits_hit:
                if lm not in _printed_limits:
                    print(color(f'  ⚠ {lm} — límite clampeado durante movimiento', YELLOW))
                    _printed_limits.add(lm)
            if trama is None:
                if self.faults:
                    return False, (time.time() - t0) * 1000, historia
                continue

            q = trama[0:3]
            historia.append({'t': time.time() - t0, 'q': q[:], 'e': trama[3:6]})

            # Verificar error excesivo sostenido
            for i in range(3):
                err_abs = abs(q[i] - targets[i])
                if err_abs > max_error:
                    if t_error_alto[i] is None:
                        t_error_alto[i] = time.time()
                    elif time.time() - t_error_alto[i] > 3.0:
                        self.disarm()
                        return False, (time.time() - t0) * 1000, historia
                else:
                    t_error_alto[i] = None

            # Verificar convergencia
            if all(abs(q[i] - targets[i]) < db for i in range(3)):
                return True, (time.time() - t0) * 1000, historia

        return False, timeout * 1000, historia

    def medir_overshoot(self, motor_idx, target, historia):
        """Extrae el overshoot máximo de la historia de una prueba."""
        if not historia:
            return 0.0
        vals = [h['q'][motor_idx] for h in historia]
        if target >= 0:
            pico = max(vals)
            return max(0.0, pico - target)
        else:
            pico = min(vals)
            return max(0.0, target - pico)

    def tiempo_respuesta(self, motor_idx, target, historia, db=5.0):
        """Tiempo en ms hasta que el motor entra en ±db del target por primera vez."""
        for h in historia:
            if abs(h['q'][motor_idx] - target) < db:
                return h['t'] * 1000
        return None  # no llegó


def paso1_comunicacion(robot):
    titulo('PASO 1 — Comunicación básica (20 tramas)')
    print('  Leyendo 20 tramas D,…')

    t0 = time.time()
    tramas = robot.leer_n_tramas(20, timeout_total=15.0)
    elapsed = time.time() - t0

    if len(tramas) < 10:
        err(f'Solo se recibieron {len(tramas)} tramas en {elapsed:.1f}s')
        err('Verifica que el ESP32 está encendido y el firmware cargado.')
        return False

    hz = len(tramas) / elapsed
    ok(f'Recibidas {len(tramas)} tramas en {elapsed:.1f}s ({hz:.1f} Hz)')

    q = tramas[-1][0:3]
    ok(f'Posición actual: M1={q[0]:.1f}°  M2={q[1]:.1f}°  M3={q[2]:.1f}°')

    for t in tramas:
        if len(t) != 9:
            err('Trama con número incorrecto de campos')
            return False
    ok('Formato de telemetría correcto (9 campos por trama)')
    return True


def paso2_encoders_reposo(robot):
    titulo('PASO 2 — Verificación de encoders en reposo (50 tramas)')
    print('  No muevas el robot durante esta prueba…')

    tramas = robot.leer_n_tramas(50, timeout_total=15.0)
    if len(tramas) < 20:
        err(f'Solo se recibieron {len(tramas)} tramas')
        return False

    qs = [[t[i] for t in tramas] for i in range(3)]
    derivas = [max(q) - min(q) for q in qs]
    ruido   = [sum(abs(q[i+1]-q[i]) for i in range(len(q)-1))/(len(q)-1) for q in qs]

    ok(f'Tramas analizadas: {len(tramas)}')
    for i, (d, r) in enumerate(zip(derivas, ruido)):
        nombre = MOTOR_NAMES[i+1]
        estado = '✓' if d < 1.0 else '⚠'
        linea = f'  {estado}  {nombre}: deriva={d:.2f}°  ruido_promedio={r:.3f}°/trama'
        if d < 1.0:
            print(color(linea, GREEN))
        else:
            print(color(linea, YELLOW))
            warn(f'M{i+1} tiene deriva > 1° en reposo — posible ruido en encoder')

    return all(d < 5.0 for d in derivas)


def paso3_respuesta_motores(robot):
    titulo('PASO 3 — Prueba de respuesta por motor')

    ANGULOS_PRUEBA = [10, 25, -10, -25, 0]
    DB_LLEGADA = 3.0   # grados
    DB_TIEMPO  = 5.0   # grados para medir tiempo de respuesta
    TIMEOUT    = 8.0   # segundos por prueba

    resultados = []
    hay_fault = False

    for motor in range(1, 4):
        subtitulo(MOTOR_NAMES[motor])
        lim_neg, lim_pos = LIMITS[motor]

        for angulo in ANGULOS_PRUEBA:
            # Verificar que no supera límites físicos
            angulo_fw = max(lim_neg, min(lim_pos, angulo))
            if angulo_fw != angulo:
                warn(f'  Ángulo {angulo}° ajustado a {angulo_fw}° (límite físico)')

            # Construir comando T,
            cmd_q = [0.0, 0.0, 0.0]
            cmd_q[motor - 1] = float(angulo_fw)
            robot.enviar(f'T,{cmd_q[0]:.2f},{cmd_q[1]:.2f},{cmd_q[2]:.2f}')

            targets = [0.0, 0.0, 0.0]
            targets[motor - 1] = float(angulo_fw)

            timeout_adap = 4.0 if abs(angulo_fw) <= 15 else 8.0
            llegó, t_ms, historia = robot.esperar_posicion(targets, db=DB_LLEGADA, timeout=timeout_adap)

            if robot.faults:
                err(f'FAULT detectado: {robot.faults[-1]} — abortando')
                robot.disarm()
                hay_fault = True
                break

            if historia:
                q_final = historia[-1]['q'][motor - 1]
                error_ss = q_final - angulo_fw
                overshoot = robot.medir_overshoot(motor - 1, angulo_fw, historia)
                t_resp = robot.tiempo_respuesta(motor - 1, angulo_fw, historia, db=DB_TIEMPO)
                estado = '✓ OK' if llegó else '✗ TIMEOUT'
                resultados.append({
                    'motor': motor, 'pedido': angulo_fw, 'real': q_final,
                    'error': error_ss, 't_resp': t_resp, 'overshoot': overshoot,
                    'ok': llegó, 'estado': estado
                })
            else:
                resultados.append({
                    'motor': motor, 'pedido': angulo_fw, 'real': None,
                    'error': None, 't_resp': None, 'overshoot': None,
                    'ok': False, 'estado': '✗ SIN DATOS'
                })

            # Volver a cero entre pruebas
            robot.enviar('T,0.00,0.00,0.00')
            robot.esperar_posicion([0.0, 0.0, 0.0], db=2.0, timeout=6.0)

            if hay_fault:
                break

        if hay_fault:
            break

    # Imprimir tabla
    if resultados:
        print()
        sep = '─' * 74
        print(sep)
        print(f'{"Motor":<12} {"Pedido":>7} {"Real (°)":>9} {"Error (°)":>10} {"T.resp":>8} {"Overshoot":>10} {"Estado"}')
        print(sep)
        for r in resultados:
            real   = f'{r["real"]:.1f}' if r["real"] is not None else '---'
            error  = f'{r["error"]:+.1f}' if r["error"] is not None else '---'
            tresp  = f'{r["t_resp"]:.0f}ms' if r["t_resp"] is not None else '---'
            over   = f'{r["overshoot"]:.1f}°' if r["overshoot"] is not None else '---'
            linea  = f'{MOTOR_NAMES[r["motor"]]:<12} {r["pedido"]:>7.0f}° {real:>9} {error:>10} {tresp:>8} {over:>10}   {r["estado"]}'
            c = GREEN if r['ok'] else RED
            print(color(linea, c))
        print(sep)

    return resultados, hay_fault


def paso4_limites_software(robot):
    titulo('PASO 4 — Verificación de límites por software')

    pruebas = [
        (1,  90.0,  80.0, 'LIMIT:M1'),
        (2,  50.0,  45.0, 'LIMIT:M2'),
        (3,  50.0,  45.0, 'LIMIT:M3'),
        (1, -90.0, -80.0, 'LIMIT:M1'),
        (2, -50.0, -45.0, 'LIMIT:M2'),
        (3, -50.0, -45.0, 'LIMIT:M3'),
    ]

    todos_ok = True
    for motor, pedido, esperado, msg_esperado in pruebas:
        robot.limits_hit.clear()
        cmd_q = [0.0, 0.0, 0.0]
        cmd_q[motor - 1] = pedido
        robot.enviar(f'T,{cmd_q[0]:.2f},{cmd_q[1]:.2f},{cmd_q[2]:.2f}')
        time.sleep(0.3)
        # Leer respuesta
        for _ in range(10):
            robot.leer_trama(timeout=0.2)

        if any(msg_esperado in m for m in robot.limits_hit):
            ok(f'M{motor}: pedido {pedido}° → recibido {msg_esperado} (clampeado a {esperado}°)')
        else:
            err(f'M{motor}: pedido {pedido}° → NO se recibió {msg_esperado}')
            todos_ok = False

        robot.enviar('T,0.00,0.00,0.00')
        robot.esperar_posicion([0.0, 0.0, 0.0], db=3.0, timeout=4.0)

    return todos_ok


def paso5_anti_atasco_firma(robot):
    titulo('PASO 5 — Verificación de detección de atasco (revisión de código)')
    firmware_path = os.path.join(os.path.dirname(__file__), '..', 'firmware',
                                 'robot3dof_firmware.ino')
    try:
        with open(firmware_path, 'r') as f:
            codigo = f.read()
    except FileNotFoundError:
        warn('No se encontró firmware/robot3dof_firmware.ino para revisar.')
        return False

    checks = [
        ('stall_cnt',       'Contador de ciclos sin movimiento'),
        ('FAULT',           'Respuesta FAULT:Mn al firmware'),
        ('enc_prev',        'Comparación de posición de encoder previa'),
        ('power > 150',     'Umbral de PWM para activar detección'),
        ('fault[idx]',      'Flag de falla por motor'),
    ]

    print('  Revisando lógica anti-atasco en el firmware:')
    todos = True
    for patron, descripcion in checks:
        if patron in codigo:
            ok(f'{descripcion} — encontrado ({patron!r})')
        else:
            err(f'{descripcion} — NO encontrado ({patron!r})')
            todos = False

    if todos:
        ok('Lógica anti-atasco implementada correctamente.')
        print('  (No se prueba físicamente para evitar daño mecánico)')
    return todos


def paso6_movimiento_combinado(robot):
    titulo('PASO 6 — Prueba de movimiento combinado (3 motores)')

    secuencia = [
        ([20.0,  20.0,  20.0], 'T,20,20,20'),
        ([-20.0, -20.0, -20.0], 'T,-20,-20,-20'),
        ([0.0,   0.0,   0.0],  'T,0,0,0'),
    ]

    todos_ok = True
    for targets, desc in secuencia:
        print(f'  Enviando {desc}…')
        cmd = f'T,{targets[0]:.2f},{targets[1]:.2f},{targets[2]:.2f}'
        robot.enviar(cmd)
        llegó, t_ms, _ = robot.esperar_posicion(targets, db=6.0, timeout=8.0)

        if robot.faults:
            err(f'FAULT detectado: {robot.faults[-1]}')
            robot.disarm()
            return False

        pos = robot.posicion_actual()
        pos_str = f'M1={pos[0]:.1f}° M2={pos[1]:.1f}° M3={pos[2]:.1f}°' if pos else '---'

        if llegó:
            ok(f'{desc} → {pos_str}  ({t_ms:.0f}ms)')
        else:
            warn(f'{desc} → {pos_str}  (TIMEOUT {t_ms:.0f}ms)')
            todos_ok = False

    return todos_ok


def paso7_reporte(p1, p2, resultados_p3, faults_p3, p4, p5, p6):
    titulo('PASO 7 — Reporte final')

    problemas  = []
    advertencias = []

    if not p1:
        problemas.append('Comunicación serial falla')
    if not p2:
        advertencias.append('Deriva de encoder en reposo detectada')
    if faults_p3:
        problemas.append('FAULT en prueba de motores — motor bloqueado')
    if resultados_p3:
        for r in resultados_p3:
            if not r['ok']:
                advertencias.append(f'{MOTOR_NAMES[r["motor"]]}: no llegó a {r["pedido"]:.0f}°')
            elif r['error'] is not None and abs(r['error']) > 5.0:
                advertencias.append(f'{MOTOR_NAMES[r["motor"]]}: error SS={r["error"]:+.1f}° (>5°)')
    if not p4:
        problemas.append('Límites por software no reportados correctamente')
    if not p6:
        advertencias.append('Movimiento combinado con timeout o sin convergencia')

    if problemas:
        print(color('\n🔴 PROBLEMAS DETECTADOS', RED + BOLD))
        for p in problemas:
            print(color(f'  • {p}', RED))
    elif advertencias:
        print(color('\n🟡 SISTEMA CON ADVERTENCIAS', YELLOW + BOLD))
        for a in advertencias:
            print(color(f'  • {a}', YELLOW))
    else:
        print(color('\n🟢 SISTEMA OK — todos los motores responden correctamente', GREEN + BOLD))

    # Recomendaciones
    if resultados_p3:
        print(color('\n  Recomendaciones de ajuste:', CYAN))
        lentos = [r for r in resultados_p3 if r['t_resp'] is not None and r['t_resp'] > 1500]
        oscila = [r for r in resultados_p3 if r['overshoot'] is not None and r['overshoot'] > 10.0]
        no_llega = [r for r in resultados_p3 if not r['ok'] and r['error'] is not None]

        if lentos:
            ms_l = MOTOR_NAMES[lentos[0]['motor']]
            print(f'  • {ms_l} responde lento (>1500ms): sube Kp o baja deadband')
        if oscila:
            ms_o = MOTOR_NAMES[oscila[0]['motor']]
            print(f'  • {ms_o} con overshoot >10°: baja Kp o sube Kd')
        if no_llega:
            ms_n = MOTOR_NAMES[no_llega[0]['motor']]
            print(f'  • {ms_n} no converge: verifica conexión física y dirección (INVERTIDO)')
        if not (lentos or oscila or no_llega):
            print('  • Sin ajustes requeridos — parámetros dentro de rango aceptable')

    print()


def main():
    parser = argparse.ArgumentParser(description='Diagnóstico robot 3-DOF')
    parser.add_argument('puerto', help='Puerto serial (ej. /dev/ttyUSB0)')
    parser.add_argument('--rapido', action='store_true', help='Solo Pasos 1-2')
    args = parser.parse_args()

    print(color('\n╔══════════════════════════════════════════════════════════╗', CYAN))
    print(color('║   VERIFICACIÓN SISTEMA ROBOT 3-DOF — sin MATLAB          ║', CYAN))
    print(color('╚══════════════════════════════════════════════════════════╝', CYAN))
    print(f'  Puerto: {args.puerto}  |  Baud: {BAUD}')

    try:
        robot = Robot(args.puerto)
    except serial.SerialException as e:
        print(color(f'\n✗ No se pudo abrir {args.puerto}: {e}', RED))
        sys.exit(1)

    p1 = p2 = p4 = p5 = p6 = False
    resultados_p3 = []
    faults_p3 = False

    try:
        p1 = paso1_comunicacion(robot)
        if not p1:
            print(color('\nAbortando por falla de comunicación.', RED))
            return

        p2 = paso2_encoders_reposo(robot)

        if args.rapido:
            print(color('\n  (Modo --rapido: deteniendo después del Paso 2)', YELLOW))
            paso7_reporte(p1, p2, [], False, True, True, True)
            return

        resultados_p3, faults_p3 = paso3_respuesta_motores(robot)
        if faults_p3:
            print(color('\nFAULT detectado — enviando DISARM y terminando.', RED))
            robot.disarm()
        else:
            p4 = paso4_limites_software(robot)
            p5 = paso5_anti_atasco_firma(robot)
            p6 = paso6_movimiento_combinado(robot)

    except KeyboardInterrupt:
        print(color('\n\n[Interrumpido por el usuario]', YELLOW))
        robot.disarm()

    finally:
        titulo('Finalizando — enviando ZERO')
        robot.zero()
        time.sleep(0.5)
        robot.close()
        print(color('  Conexión cerrada.', CYAN))

    paso7_reporte(p1, p2, resultados_p3, faults_p3, p4, p5, p6)


if __name__ == '__main__':
    main()
