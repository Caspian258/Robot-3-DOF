#!/usr/bin/env python3
"""
Bridge serial para Robot 3-DOF
Evita problemas de lock files de MATLAB en Linux
"""

import serial
import sys
import time
from threading import Thread

class RobotBridge:
    def __init__(self, port='/dev/ttyUSB0', baudrate=115200):
        self.port = port
        self.baudrate = baudrate
        self.ser = None
        self.running = False
        
    def connect(self):
        try:
            self.ser = serial.Serial(self.port, self.baudrate, timeout=1)
            time.sleep(0.5)
            print(f"✓ Conectado a {self.port} @ {self.baudrate} baud")
            self.running = True
            return True
        except Exception as e:
            print(f"✗ Error de conexión: {e}")
            return False
    
    def send(self, cmd):
        """Enviar comando al ESP32"""
        if self.ser and self.ser.is_open:
            self.ser.write((cmd + '\n').encode())
            return True
        return False
    
    def read_line(self):
        """Leer línea del ESP32"""
        if self.ser and self.ser.is_open:
            try:
                line = self.ser.readline().decode().strip()
                return line
            except:
                pass
        return None
    
    def close(self):
        if self.ser and self.ser.is_open:
            self.ser.close()
            print("✓ Desconectado")

# Ejemplo de uso
if __name__ == "__main__":
    bridge = RobotBridge()
    
    if not bridge.connect():
        sys.exit(1)
    
    # Enviar test
    print("\nEnviando SP:45.0,30.0,0.0...")
    bridge.send("SP:45.0,30.0,0.0")
    
    # Leer respuestas
    for i in range(10):
        line = bridge.read_line()
        if line:
            print(f"← {line}")
        time.sleep(0.1)
    
    bridge.close()
