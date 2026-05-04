#include <Arduino.h>
#include <micro_ros_platformio.h>
#include <rcl/rcl.h>
#include <rclc/rclc.h>
#include <rclc/executor.h>
#include <std_msgs/msg/float64.h>

// ─── Motor count ─────────────────────────────────────────────────────
#define NUM_MOTORS 3

// ─── Pin definitions ─────────────────────────────────────────────────
//                        Motor:  1    2    3
const int PIN_ENC_A[NUM_MOTORS] = {18,  32,  4};
const int PIN_ENC_B[NUM_MOTORS] = {19,  33,  5};
const int PIN_IN1  [NUM_MOTORS] = {15,  21,  26};
const int PIN_IN2  [NUM_MOTORS] = {2,  22,  27};
const int PIN_ENA  [NUM_MOTORS] = {25,  23,  17};
const int PWM_CH   [NUM_MOTORS] = { 0,   1,   2};

// ─── Motor / encoder parameters ──────────────────────────────────────
#define COUNTS_PER_REV  486.0f

// [NEW] Define the minimum PWM needed to overcome stiction
#define MIN_PWM 18.0f 

// ─── PWM config ──────────────────────────────────────────────────────
const int PWM_FREQ = 20000;
const int PWM_BITS = 8;

// ─── Controller state ────────────────────────────────────────────────
volatile long encoderCount[NUM_MOTORS] = {0, 0, 0};
float setpoint_deg[NUM_MOTORS]         = {0, 0, 0};
float prevError   [NUM_MOTORS]         = {0, 0, 0}; 
float Kp = 0.0f;
float Kd = 0.0f;
unsigned long prevTime = 0;

// ─── Encoder ISRs ────────────────────────────────────────────────────
void IRAM_ATTR isr0() { encoderCount[0] += digitalRead(PIN_ENC_B[0]) ? 1 : -1; }
void IRAM_ATTR isr1() { encoderCount[1] += digitalRead(PIN_ENC_B[1]) ? 1 : -1; }
void IRAM_ATTR isr2() { encoderCount[2] += digitalRead(PIN_ENC_B[2]) ? 1 : -1; }

// ─── micro-ROS objects ───────────────────────────────────────────────
rcl_node_t       node;
rclc_support_t   support;
rcl_allocator_t  allocator;
rclc_executor_t  executor;

rcl_publisher_t    pub_pos[NUM_MOTORS];
rcl_subscription_t sub_sp [NUM_MOTORS];
rcl_subscription_t sub_kp, sub_kd;

std_msgs__msg__Float64 msg_pos[NUM_MOTORS];
std_msgs__msg__Float64 msg_sp [NUM_MOTORS];
std_msgs__msg__Float64 msg_kp_in, msg_kd_in;

// ─── Subscription callbacks ──────────────────────────────────────────
void sp0_cb(const void* m) { setpoint_deg[0] = (float)((std_msgs__msg__Float64*)m)->data; }
void sp1_cb(const void* m) { setpoint_deg[1] = (float)((std_msgs__msg__Float64*)m)->data; }
void sp2_cb(const void* m) { setpoint_deg[2] = (float)((std_msgs__msg__Float64*)m)->data; }
void kp_cb (const void* m) { Kp = (float)((std_msgs__msg__Float64*)m)->data; }
void kd_cb (const void* m) { Kd = (float)((std_msgs__msg__Float64*)m)->data; }

// ─── Motor output ────────────────────────────────────────────────────
void setMotor(int i, float output) {
  int duty = (int)constrain(fabsf(output), 0, 255);
  if (output > 0) {
    digitalWrite(PIN_IN1[i], HIGH);
    digitalWrite(PIN_IN2[i], LOW);
  } else if (output < 0) {
    digitalWrite(PIN_IN1[i], LOW);
    digitalWrite(PIN_IN2[i], HIGH);
  } else {
    digitalWrite(PIN_IN1[i], LOW);
    digitalWrite(PIN_IN2[i], LOW);
  }
  ledcWrite(PWM_CH[i], duty);
}

// ─── Setup ───────────────────────────────────────────────────────────
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

  // ── micro-ROS ────────────────────────────────────────────────────
  set_microros_serial_transports(Serial);
  delay(2000);

  allocator = rcl_get_default_allocator();
  rclc_support_init(&support, 0, NULL, &allocator);
  rclc_node_init_default(&node, "motor_pd_node", "", &support);

  char buf[48];
  for (int i = 0; i < NUM_MOTORS; i++) {
    snprintf(buf, sizeof(buf), "motor/m%d/position", i + 1);
    rclc_publisher_init_default(&pub_pos[i], &node,
      ROSIDL_GET_MSG_TYPE_SUPPORT(std_msgs, msg, Float64), buf);

    snprintf(buf, sizeof(buf), "motor/m%d/setpoint", i + 1);
    rclc_subscription_init_default(&sub_sp[i], &node,
      ROSIDL_GET_MSG_TYPE_SUPPORT(std_msgs, msg, Float64), buf);
  }

  rclc_subscription_init_default(&sub_kp, &node,
    ROSIDL_GET_MSG_TYPE_SUPPORT(std_msgs, msg, Float64), "motor/kp");
  rclc_subscription_init_default(&sub_kd, &node,
    ROSIDL_GET_MSG_TYPE_SUPPORT(std_msgs, msg, Float64), "motor/kd");

  rclc_executor_init(&executor, &support.context, 5, &allocator);

  rclc_executor_add_subscription(&executor, &sub_sp[0], &msg_sp[0], sp0_cb, ON_NEW_DATA);
  rclc_executor_add_subscription(&executor, &sub_sp[1], &msg_sp[1], sp1_cb, ON_NEW_DATA);
  rclc_executor_add_subscription(&executor, &sub_sp[2], &msg_sp[2], sp2_cb, ON_NEW_DATA);
  rclc_executor_add_subscription(&executor, &sub_kp, &msg_kp_in, kp_cb, ON_NEW_DATA);
  rclc_executor_add_subscription(&executor, &sub_kd, &msg_kd_in, kd_cb, ON_NEW_DATA);

  prevTime = millis();
}

// ─── Loop ────────────────────────────────────────────────────────────
void loop() {
  rclc_executor_spin_some(&executor, RCL_MS_TO_NS(10));

  unsigned long now = millis();
  float dt = (now - prevTime) / 1000.0f; 
  
  if (dt < 0.05f) return;   // 100 Hz
  prevTime = now;

  for (int i = 0; i < NUM_MOTORS; i++) {
    float angle = ((float)encoderCount[i] / COUNTS_PER_REV) * 360.0f;
    float error = setpoint_deg[i] - angle;

    float derivative = (error - prevError[i]) / dt;
    float output = (Kp * error) + (Kd * derivative);
    
    // [NEW] Stiction deadband compensation
    if (output > 0.5f) {
      output += MIN_PWM;
    } else if (output < -0.5f) {
      output -= MIN_PWM;
    } else {
      output = 0.0f; // Silence jitter exactly at 0
    }
    
    prevError[i] = error;

    setMotor(i, output);

    msg_pos[i].data = (double)angle;
    (void)rcl_publish(&pub_pos[i], &msg_pos[i], NULL);
  }
}