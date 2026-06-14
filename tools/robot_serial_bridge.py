#!/usr/bin/env python3
"""
robot_serial_bridge.py — Bridge serial para Robot 3DOF (Linux)

Problema que resuelve:
  MATLAB en Linux intenta crear lock files en /run/lock (p.ej. LCK..ttyUSB0).
  Si ese directorio no tiene permisos de escritura para el usuario, MATLAB
  no puede abrir el puerto serial aunque el usuario esté en el grupo dialout.

Solución:
  Este script abre el puerto y expone un socket TCP local (127.0.0.1:5005).
  MATLAB (u otro cliente) se conecta al socket y envía/recibe exactamente los
  mismos comandos que enviaría directo al ESP32 — el bridge los retransmite.

Uso:
  1. Correr este script ANTES de abrir MATLAB:
       python3 robot_serial_bridge.py
       python3 robot_serial_bridge.py --port /dev/ttyUSB1  # si el puerto es distinto

  2. En MATLAB, conectarse a 127.0.0.1:5005 en vez del puerto serial directo.
     (Alternativamente: aplicar el fix de permisos y usar MATLAB directo)

Fix de permisos (alternativa sin bridge):
  sudo chmod 1777 /run/lock
  Para que persista al reiniciar:
  echo "d /run/lock 1777 root root -" | sudo tee /etc/tmpfiles.d/run-lock-open.conf
"""

import argparse
import socket
import threading
import sys
import time

try:
    import serial
except ImportError:
    print("[ERROR] pyserial no está instalado.")
    print("        Instálalo con: pip install pyserial")
    sys.exit(1)

SERIAL_PORT = "/dev/ttyUSB0"
SERIAL_BAUD = 115200
TCP_HOST    = "127.0.0.1"
TCP_PORT    = 5005


def serial_to_tcp(ser, conn):
    """Lee del serial, escribe al socket TCP."""
    try:
        while True:
            line = ser.readline()
            if not line:
                continue
            conn.sendall(line)
    except Exception:
        pass


def tcp_to_serial(ser, conn):
    """Lee del socket TCP, escribe al serial."""
    try:
        buf = b""
        while True:
            data = conn.recv(256)
            if not data:
                break
            buf += data
            while b"\n" in buf:
                idx  = buf.index(b"\n")
                line = buf[: idx + 1]
                buf  = buf[idx + 1 :]
                ser.write(line)
    except Exception:
        pass


def run_bridge(serial_port: str):
    print(f"[bridge] Abriendo {serial_port} a {SERIAL_BAUD} baud...")
    try:
        ser = serial.Serial(serial_port, SERIAL_BAUD, timeout=0.1)
    except serial.SerialException as e:
        print(f"[ERROR] No se pudo abrir {serial_port}: {e}")
        sys.exit(1)

    time.sleep(2)  # esperar reset del ESP32 al abrir el puerto
    print(f"[bridge] ESP32 listo. Escuchando en {TCP_HOST}:{TCP_PORT} ...")

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((TCP_HOST, TCP_PORT))
    srv.listen(1)
    print("[bridge] Esperando conexión de MATLAB...")

    try:
        while True:
            conn, addr = srv.accept()
            print(f"[bridge] Cliente conectado: {addr}")
            t1 = threading.Thread(target=serial_to_tcp, args=(ser, conn), daemon=True)
            t2 = threading.Thread(target=tcp_to_serial, args=(ser, conn), daemon=True)
            t1.start()
            t2.start()
            t1.join()
            t2.join()
            conn.close()
            print("[bridge] Cliente desconectado. Esperando nueva conexión...")
    except KeyboardInterrupt:
        print("\n[bridge] Cerrando.")
    finally:
        ser.close()
        srv.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Bridge serial→TCP para Robot 3DOF")
    parser.add_argument(
        "--port",
        default=SERIAL_PORT,
        help=f"Puerto serial del ESP32 (default: {SERIAL_PORT})",
    )
    args = parser.parse_args()
    run_bridge(args.port)
