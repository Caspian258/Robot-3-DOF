// =============================================================================
// Robot 3-DOF — Firmware ESP32 para MATLAB (Serial USB)
// Protocolo: MATLAB envía "SP:deg1,deg2,deg3\n"  (setpoints en grados)
//            ESP32 responde "POS:deg1,deg2,deg3\n" (posiciones actuales)
//            MATLAB puede enviar "KP:valor\n" y "KD:valor\n"
//            MATLAB puede enviar "RST\n" para resetear encoders
// =============================================================================
// PINS VERIFICADOS FÍSICAMENTE
//   M1: ENC_A=18  ENC_B=19  IN1=25  IN2=26  ENA=27
//   M2: ENC_A=32  ENC_B=33  IN1=21  IN2=22  ENA=23
//   M3: ENC_A=34  ENC_B=35  IN1=13  IN2=14  ENA=16
// =============================================================================

#define NUM_MOTORS     3
#define COUNTS_PER_REV 994.0f   // Actualizado por usuario
#define MIN_PWM        18.0f    // Stiction deadband
#define PWM_FREQ       20000
#define PWM_BITS       8
#define CONTROL_HZ     50       // Frecuencia de control (ms)
#define SERIAL_HZ      20       // Frecuencia de reporte a MATLAB (ms)

// ── Pins ──────────────────────────────────────────────────────────────────────
const int PIN_ENC_A[NUM_MOTORS] = {18, 32, 34};
const int PIN_ENC_B[NUM_MOTORS] = {19, 33, 35};
const int PIN_IN1  [NUM_MOTORS] = {25, 21, 13};
const int PIN_IN2  [NUM_MOTORS] = {26, 22, 14};
const int PIN_ENA  [NUM_MOTORS] = {27, 23, 16};
const int PWM_CH   [NUM_MOTORS] = { 0,  1,  2};

// ── Estado ────────────────────────────────────────────────────────────────────
volatile long encoderCount[NUM_MOTORS] = {0, 0, 0};
float setpoint_deg[NUM_MOTORS]         = {0, 0, 0};
float prevError   [NUM_MOTORS]         = {0, 0, 0};
float Kp = 2.5f;
float Kd = 0.08f;

unsigned long prevControlTime = 0;
unsigned long prevSerialTime  = 0;

// ── ISRs ──────────────────────────────────────────────────────────────────────
void IRAM_ATTR isr0() { encoderCount[0] += digitalRead(PIN_ENC_B[0]) ? 1 : -1; }
void IRAM_ATTR isr1() { encoderCount[1] += digitalRead(PIN_ENC_B[1]) ? 1 : -1; }
void IRAM_ATTR isr2() { encoderCount[2] += digitalRead(PIN_ENC_B[2]) ? 1 : -1; }

// ── Motor output ──────────────────────────────────────────────────────────────
void setMotor(int i, float output) {
  int duty = (int)constrain(fabsf(output), 0, 255);
  if (output > 0.5f) {
    digitalWrite(PIN_IN1[i], HIGH);
    digitalWrite(PIN_IN2[i], LOW);
    ledcWrite(PWM_CH[i], duty + (int)MIN_PWM);
  } else if (output < -0.5f) {
    digitalWrite(PIN_IN1[i], LOW);
    digitalWrite(PIN_IN2[i], HIGH);
    ledcWrite(PWM_CH[i], duty + (int)MIN_PWM);
  } else {
    digitalWrite(PIN_IN1[i], LOW);
    digitalWrite(PIN_IN2[i], LOW);
    ledcWrite(PWM_CH[i], 0);
  }
}

// ── Parser Serial ─────────────────────────────────────────────────────────────
void parseSerial(String line) {
  line.trim();

  // SP:90.0,45.0,-30.0
  if (line.startsWith("SP:")) {
    String data = line.substring(3);
    int c1 = data.indexOf(',');
    int c2 = data.indexOf(',', c1 + 1);
    if (c1 > 0 && c2 > c1) {
      setpoint_deg[0] = data.substring(0, c1).toFloat();
      setpoint_deg[1] = data.substring(c1 + 1, c2).toFloat();
      setpoint_deg[2] = data.substring(c2 + 1).toFloat();
    }
  }
  // KP:3.5
  else if (line.startsWith("KP:")) {
    Kp = line.substring(3).toFloat();
  }
  // KD:0.1
  else if (line.startsWith("KD:")) {
    Kd = line.substring(3).toFloat();
  }
  // RST — resetear encoders a cero
  else if (line == "RST") {
    for (int i = 0; i < NUM_MOTORS; i++) {
      encoderCount[i] = 0;
      setpoint_deg[i] = 0;
      prevError[i]    = 0;
      setMotor(i, 0);
    }
    Serial.println("ACK:RST");
  }
  // STOP — apagar motores sin resetear
  else if (line == "STOP") {
    for (int i = 0; i < NUM_MOTORS; i++) {
      setpoint_deg[i] = (encoderCount[i] / COUNTS_PER_REV) * 360.0f;
    }
    Serial.println("ACK:STOP");
  }
}

// ── Setup ─────────────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);

  for (int i = 0; i < NUM_MOTORS; i++) {
    pinMode(PIN_IN1[i], OUTPUT);
    pinMode(PIN_IN2[i], OUTPUT);
    ledcSetup(PWM_CH[i], PWM_FREQ, PWM_BITS);
    ledcAttachPin(PIN_ENA[i], PWM_CH[i]);

    bool hasPullup = (PIN_ENC_A[i] < 34);
    pinMode(PIN_ENC_A[i], hasPullup ? INPUT_PULLUP : INPUT);
    pinMode(PIN_ENC_B[i], hasPullup ? INPUT_PULLUP : INPUT);
  }

  attachInterrupt(digitalPinToInterrupt(PIN_ENC_A[0]), isr0, RISING);
  attachInterrupt(digitalPinToInterrupt(PIN_ENC_A[1]), isr1, RISING);
  attachInterrupt(digitalPinToInterrupt(PIN_ENC_A[2]), isr2, RISING);

  Serial.println("READY:Robot3DOF");
}

// ── Loop ──────────────────────────────────────────────────────────────────────
void loop() {
  unsigned long now = millis();

  // ── Leer Serial ─────────────────────────────────────────────────────────
  if (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    parseSerial(line);
  }

  // ── Control PD @ CONTROL_HZ ─────────────────────────────────────────────
  float dt = (now - prevControlTime) / 1000.0f;
  if (dt >= (1.0f / CONTROL_HZ)) {
    prevControlTime = now;
    for (int i = 0; i < NUM_MOTORS; i++) {
      float angle = (encoderCount[i] / COUNTS_PER_REV) * 360.0f;
      float error = setpoint_deg[i] - angle;
      float deriv = (error - prevError[i]) / dt;
      float output = (Kp * error) + (Kd * deriv);
      output = constrain(output, -255, 255);
      prevError[i] = error;
      setMotor(i, output);
    }
  }

  // ── Reporte a MATLAB @ SERIAL_HZ ────────────────────────────────────────
  if ((now - prevSerialTime) >= (1000 / SERIAL_HZ)) {
    prevSerialTime = now;
    float a0 = (encoderCount[0] / COUNTS_PER_REV) * 360.0f;
    float a1 = (encoderCount[1] / COUNTS_PER_REV) * 360.0f;
    float a2 = (encoderCount[2] / COUNTS_PER_REV) * 360.0f;
    // Formato: POS:deg1,deg2,deg3,sp1,sp2,sp3
    Serial.print("POS:");
    Serial.print(a0, 2); Serial.print(",");
    Serial.print(a1, 2); Serial.print(",");
    Serial.print(a2, 2); Serial.print(",");
    Serial.print(setpoint_deg[0], 2); Serial.print(",");
    Serial.print(setpoint_deg[1], 2); Serial.print(",");
    Serial.println(setpoint_deg[2], 2);
  }
}
