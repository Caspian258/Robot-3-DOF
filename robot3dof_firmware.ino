#include <Arduino.h>

// =============================================================
//  Robot RRR 3DOF - Firmware ESP32
//  Control PD con estado HOLDING: al estabilizarse corta energía
//  y no vuelve a escribir pines hasta recibir nuevo target.
// =============================================================

// --- PINES DE POTENCIA (verificados físicamente) ---
const int M1_IN1 = 15; const int M1_IN2 = 2;  const int M1_ENA = 25;
const int M2_IN1 = 21; const int M2_IN2 = 22; const int M2_ENA = 23;
const int M3_IN1 = 26; const int M3_IN2 = 27; const int M3_ENA = 17;

// --- PINES DE ENCODERS (verificados físicamente) ---
const int M1_ENCA = 18; const int M1_ENCB = 19;
const int M2_ENCA = 32; const int M2_ENCB = 33;
const int M3_ENCA = 4;  const int M3_ENCB = 5;

// --- CONSTANTES ---
const float PULSOS_POR_VUELTA = 1200.0f;

// --- TARGETS Y POSICIÓN ---
float target_q[3]  = {0.0f, 0.0f, 0.0f};
float current_q[3] = {0.0f, 0.0f, 0.0f};

// --- GANANCIAS PD ---
float Kp[3] = {2.0f,  2.5f,  2.5f};
float Kd[3] = {0.05f, 0.05f, 0.05f};

// --- ZONA MUERTA (grados) — 5° validado en prueba física ---
float deadband[3] = {5.0f, 5.0f, 5.0f};

// --- ESTADO POR MOTOR ---
// false = controlando activamente, true = ya llegó y está en reposo
bool holding[3] = {false, false, false};

// --- CONTADORES DE ENCODER ---
volatile long encCount[3] = {0, 0, 0};

// --- PD internos ---
float prev_error[3]     = {0, 0, 0};
unsigned long last_t[3] = {0, 0, 0};
int pwm_out[3]          = {0, 0, 0};

// ---------------------------------------------------------------
//  ISRs — Quadratura completa (CHANGE en A y B)
// ---------------------------------------------------------------
void IRAM_ATTR isr_M1_A() {
  encCount[0] += (digitalRead(M1_ENCA) == digitalRead(M1_ENCB)) ? 1 : -1;
}
void IRAM_ATTR isr_M1_B() {
  encCount[0] += (digitalRead(M1_ENCA) != digitalRead(M1_ENCB)) ? 1 : -1;
}
void IRAM_ATTR isr_M2_A() {
  encCount[1] += (digitalRead(M2_ENCA) == digitalRead(M2_ENCB)) ? 1 : -1;
}
void IRAM_ATTR isr_M2_B() {
  encCount[1] += (digitalRead(M2_ENCA) != digitalRead(M2_ENCB)) ? 1 : -1;
}
void IRAM_ATTR isr_M3_A() {
  encCount[2] += (digitalRead(M3_ENCA) == digitalRead(M3_ENCB)) ? 1 : -1;
}
void IRAM_ATTR isr_M3_B() {
  encCount[2] += (digitalRead(M3_ENCA) != digitalRead(M3_ENCB)) ? 1 : -1;
}

// ---------------------------------------------------------------
//  Prototipos
// ---------------------------------------------------------------
void controlMotor(int idx, int in1, int in2, int ena);
void apagarMotor(int in1, int in2, int ena);
void procesarSerial();

// ---------------------------------------------------------------
//  SETUP
// ---------------------------------------------------------------
void setup() {
  Serial.begin(115200);

  // Pines de potencia — expandidos explícitamente
  pinMode(M1_IN1, OUTPUT); pinMode(M1_IN2, OUTPUT); pinMode(M1_ENA, OUTPUT);
  pinMode(M2_IN1, OUTPUT); pinMode(M2_IN2, OUTPUT); pinMode(M2_ENA, OUTPUT);
  pinMode(M3_IN1, OUTPUT); pinMode(M3_IN2, OUTPUT); pinMode(M3_ENA, OUTPUT);
  apagarMotor(M1_IN1, M1_IN2, M1_ENA);
  apagarMotor(M2_IN1, M2_IN2, M2_ENA);
  apagarMotor(M3_IN1, M3_IN2, M3_ENA);

  // Encoders
  pinMode(M1_ENCA, INPUT_PULLUP); pinMode(M1_ENCB, INPUT_PULLUP);
  pinMode(M2_ENCA, INPUT_PULLUP); pinMode(M2_ENCB, INPUT_PULLUP);
  pinMode(M3_ENCA, INPUT_PULLUP); pinMode(M3_ENCB, INPUT_PULLUP);

  attachInterrupt(digitalPinToInterrupt(M1_ENCA), isr_M1_A, CHANGE);
  attachInterrupt(digitalPinToInterrupt(M1_ENCB), isr_M1_B, CHANGE);
  attachInterrupt(digitalPinToInterrupt(M2_ENCA), isr_M2_A, CHANGE);
  attachInterrupt(digitalPinToInterrupt(M2_ENCB), isr_M2_B, CHANGE);
  attachInterrupt(digitalPinToInterrupt(M3_ENCA), isr_M3_A, CHANGE);
  attachInterrupt(digitalPinToInterrupt(M3_ENCB), isr_M3_B, CHANGE);

  Serial.println("READY");
}

// ---------------------------------------------------------------
//  LOOP
// ---------------------------------------------------------------
void loop() {
  procesarSerial();

  // Leer encoders de forma atómica
  noInterrupts();
  long c0 = encCount[0], c1 = encCount[1], c2 = encCount[2];
  interrupts();

  current_q[0] = (c0 / PULSOS_POR_VUELTA) * 360.0f;
  current_q[1] = (c1 / PULSOS_POR_VUELTA) * 360.0f;
  current_q[2] = (c2 / PULSOS_POR_VUELTA) * 360.0f;

  controlMotor(0, M1_IN1, M1_IN2, M1_ENA);
  controlMotor(1, M2_IN1, M2_IN2, M2_ENA);
  controlMotor(2, M3_IN2, M3_IN1, M3_ENA);  // M3 invertido físicamente: IN1↔IN2

  // Telemetría: D,q1,q2,q3,e1,e2,e3,pwm1,pwm2,pwm3
  float e[3];
  for (int i = 0; i < 3; i++) e[i] = target_q[i] - current_q[i];

  Serial.print("D,");
  Serial.print(current_q[0], 2); Serial.print(",");
  Serial.print(current_q[1], 2); Serial.print(",");
  Serial.print(current_q[2], 2); Serial.print(",");
  Serial.print(e[0], 3);         Serial.print(",");
  Serial.print(e[1], 3);         Serial.print(",");
  Serial.print(e[2], 3);         Serial.print(",");
  Serial.print(pwm_out[0]);      Serial.print(",");
  Serial.print(pwm_out[1]);      Serial.print(",");
  Serial.println(pwm_out[2]);

  delay(10);
}

// ---------------------------------------------------------------
//  Control PD con estado HOLDING
//
//  Estados:
//    holding=false → aplica PD normalmente
//    holding=true  → motor en reposo total (no escribe pines),
//                    solo monitorea si el error crece de nuevo
//                    (p.ej. perturbación externa) para reactivar.
// ---------------------------------------------------------------
void controlMotor(int idx, int in1, int in2, int ena) {
  float error = target_q[idx] - current_q[idx];

  if (holding[idx]) {
    // Ya estabilizado. Si algo mueve el brazo más allá del doble
    // de la zona muerta, reactivar el control.
    if (fabsf(error) > deadband[idx] * 2.0f) {
      holding[idx] = false;
    } else {
      pwm_out[idx] = 0;
      return;  // No tocar los pines — silencio total
    }
  }

  // Dentro de zona muerta → apagar UNA vez y marcar holding
  if (fabsf(error) < deadband[idx]) {
    apagarMotor(in1, in2, ena);
    pwm_out[idx]    = 0;
    prev_error[idx] = error;
    last_t[idx]     = millis();
    holding[idx]    = true;
    return;
  }

  // Control PD activo
  unsigned long now = millis();
  float dt = (now - last_t[idx]) / 1000.0f;
  if (dt <= 0.0f) dt = 0.01f;

  float derivative = (error - prev_error[idx]) / dt;
  int power = (int)(fabsf(error * Kp[idx] + derivative * Kd[idx]));
  if (power > 255) power = 255;
  if (power < 30)  power = 30;   // mínimo para vencer fricción estática

  pwm_out[idx]    = power;
  prev_error[idx] = error;
  last_t[idx]     = now;

  if (error > 0) {
    digitalWrite(in1, HIGH); digitalWrite(in2, LOW);
  } else {
    digitalWrite(in1, LOW);  digitalWrite(in2, HIGH);
  }
  analogWrite(ena, power);
}

// Freno activo L298N: IN1=IN2=LOW + ENA=255 → brake-to-GND
// Reduce overshoot significativamente vs coast (ENA=0)
void apagarMotor(int in1, int in2, int ena) {
  digitalWrite(in1, LOW);
  digitalWrite(in2, LOW);
  analogWrite(ena, 255);
}

// ---------------------------------------------------------------
//  Parser serial
//  T,q1,q2,q3     → nuevo target (resetea holding)
//  K1/K2/K3,Kp,Kd → ganancias
//  DB,d1,d2,d3    → deadband
//  ZERO           → reset encoders
// ---------------------------------------------------------------
void procesarSerial() {
  while (Serial.available() > 0) {
    String data = Serial.readStringUntil('\n');
    data.trim();
    if (data.length() == 0) continue;

    if (data.startsWith("T,")) {
      int c1 = data.indexOf(',', 2);
      int c2 = data.indexOf(',', c1 + 1);
      if (c1 > 0 && c2 > 0) {
        target_q[0] = data.substring(2,    c1).toFloat();
        target_q[1] = data.substring(c1+1, c2).toFloat();
        target_q[2] = data.substring(c2+1).toFloat();
        // Nuevo target → salir de holding en todos los motores
        holding[0] = holding[1] = holding[2] = false;
      }

    } else if (data.startsWith("K") && data.length() > 3 && data.charAt(2) == ',') {
      int idx = data.charAt(1) - '1';
      if (idx >= 0 && idx < 3) {
        int c1 = data.indexOf(',', 3);
        if (c1 > 0) {
          Kp[idx] = data.substring(3, c1).toFloat();
          Kd[idx] = data.substring(c1 + 1).toFloat();
        }
      }

    } else if (data.startsWith("DB,")) {
      int c1 = data.indexOf(',', 3);
      int c2 = data.indexOf(',', c1 + 1);
      if (c1 > 0 && c2 > 0) {
        deadband[0] = data.substring(3,    c1).toFloat();
        deadband[1] = data.substring(c1+1, c2).toFloat();
        deadband[2] = data.substring(c2+1).toFloat();
      }

    } else if (data.equals("ZERO")) {
      noInterrupts();
      encCount[0] = encCount[1] = encCount[2] = 0;
      interrupts();
      target_q[0] = target_q[1] = target_q[2] = 0.0f;
      holding[0]  = holding[1]  = holding[2]  = false;
      Serial.println("ZEROED");
    }
  }
}