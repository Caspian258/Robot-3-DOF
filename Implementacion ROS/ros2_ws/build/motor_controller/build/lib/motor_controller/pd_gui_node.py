#!/usr/bin/env python3
"""
pd_gui_node.py — Combined single-window GUI with live plot and PD controls.
Publishes to /motor/setpoint, /motor/kp, /motor/kd
Subscribes to /motor/position
"""
import threading
import time
import tkinter as tk
from tkinter import ttk

import matplotlib
matplotlib.use('TkAgg')  # Must be set before importing pyplot
import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from matplotlib.animation import FuncAnimation
import matplotlib.gridspec as gridspec

import rclpy
from rclpy.node import Node
from std_msgs.msg import Float64


class MotorControlNode(Node):
    def __init__(self):
        super().__init__('motor_pd_gui_node')

        # Publishers
        self.pub_setpoint = self.create_publisher(Float64, 'motor/setpoint', 10)
        self.pub_kp       = self.create_publisher(Float64, 'motor/kp',       10)
        self.pub_kd       = self.create_publisher(Float64, 'motor/kd',       10)

        # Subscriber
        self.create_subscription(Float64, 'motor/position', self._pos_cb, 10)
        self.create_subscription(Float64, 'motor/setpoint', self._sp_cb,  10)

        # Data buffers (last 500 samples)
        self.times            = []
        self.positions        = []
        self.setpoints        = []
        self.start_time       = time.time()
        self.current_setpoint = 0.0
        self.current_position = 0.0
        self._lock            = threading.Lock()

    def _pos_cb(self, msg):
        with self._lock:
            t = time.time() - self.start_time
            self.times.append(t)
            self.positions.append(msg.data)
            self.setpoints.append(self.current_setpoint)
            self.current_position = msg.data
            if len(self.times) > 500:
                self.times.pop(0)
                self.positions.pop(0)
                self.setpoints.pop(0)

    def _sp_cb(self, msg):
        self.current_setpoint = msg.data

    def send(self, topic, value):
        msg = Float64()
        msg.data = float(value)
        if topic == 'setpoint': self.pub_setpoint.publish(msg)
        elif topic == 'kp':     self.pub_kp.publish(msg)
        elif topic == 'kd':     self.pub_kd.publish(msg)
        self.get_logger().info(f'[{topic}] → {value:.4f}')


class App:
    def __init__(self, node: MotorControlNode):
        self.node = node

        # ── Root window ──────────────────────────────────────────────
        self.root = tk.Tk()
        self.root.title('Motor PD Controller')
        self.root.configure(bg='#1e1e2e')
        self.root.geometry('960x680')
        self.root.minsize(800, 560)

        # Tkinter variables (must be created after root)
        self.var_sp = tk.DoubleVar(value=0.0)
        self.var_kp = tk.DoubleVar(value=2.0)
        self.var_kd = tk.DoubleVar(value=0.05)

        self._build_layout()
        self._build_plot()
        self._build_controls()
        self._start_animation()

    # ── Layout ───────────────────────────────────────────────────────
    def _build_layout(self):
        """Two-column layout: plot on left, controls on right."""
        self.root.columnconfigure(0, weight=3)
        self.root.columnconfigure(1, weight=1, minsize=260)
        self.root.rowconfigure(0, weight=1)

        self.plot_frame = tk.Frame(self.root, bg='#1e1e2e')
        self.plot_frame.grid(row=0, column=0, sticky='nsew', padx=(10, 4), pady=10)

        self.ctrl_frame = tk.Frame(self.root, bg='#2a2a3e',
                                   highlightbackground='#44445a',
                                   highlightthickness=1)
        self.ctrl_frame.grid(row=0, column=1, sticky='nsew', padx=(4, 10), pady=10)

    # ── Plot ─────────────────────────────────────────────────────────
    def _build_plot(self):
        self.fig = plt.Figure(figsize=(6, 5), dpi=100)
        self.fig.patch.set_facecolor('#1e1e2e')

        gs = gridspec.GridSpec(2, 1, figure=self.fig,
                               height_ratios=[3, 1], hspace=0.35)

        # Main angle plot
        self.ax = self.fig.add_subplot(gs[0])
        self.ax.set_facecolor('#12121f')
        self.ax.set_title('Angular position', color='#cdd6f4',
                           fontsize=11, pad=8)
        self.ax.set_xlabel('Time (s)', color='#a6adc8', fontsize=9)
        self.ax.set_ylabel('Angle (°)', color='#a6adc8', fontsize=9)
        self.ax.tick_params(colors='#6c7086', labelsize=8)
        for spine in self.ax.spines.values():
            spine.set_edgecolor('#44445a')
        self.ax.grid(True, color='#313244', linewidth=0.5)

        self.line_pos, = self.ax.plot([], [], color='#89dceb',
                                      linewidth=1.8, label='Position (°)')
        self.line_sp,  = self.ax.plot([], [], color='#fab387',
                                      linewidth=1.4, linestyle='--',
                                      label='Setpoint (°)')
        self.ax.legend(loc='upper right', fontsize=8,
                       facecolor='#2a2a3e', edgecolor='#44445a',
                       labelcolor='#cdd6f4')

        # Error plot
        self.ax2 = self.fig.add_subplot(gs[1])
        self.ax2.set_facecolor('#12121f')
        self.ax2.set_title('Error', color='#cdd6f4', fontsize=10, pad=6)
        self.ax2.set_xlabel('Time (s)', color='#a6adc8', fontsize=9)
        self.ax2.set_ylabel('Error (°)', color='#a6adc8', fontsize=9)
        self.ax2.tick_params(colors='#6c7086', labelsize=8)
        for spine in self.ax2.spines.values():
            spine.set_edgecolor('#44445a')
        self.ax2.grid(True, color='#313244', linewidth=0.5)
        self.ax2.axhline(0, color='#585b70', linewidth=0.8)

        self.line_err, = self.ax2.plot([], [], color='#f38ba8',
                                       linewidth=1.4, label='Error (°)')

        self.canvas = FigureCanvasTkAgg(self.fig, master=self.plot_frame)
        self.canvas.get_tk_widget().pack(fill='both', expand=True)

    # ── Controls ─────────────────────────────────────────────────────
    def _build_controls(self):
        f = self.ctrl_frame
        pad = {'padx': 14, 'pady': 0}

        # Title
        tk.Label(f, text='PD Controller', bg='#2a2a3e',
                 fg='#cdd6f4', font=('', 13, 'bold')).pack(pady=(18, 14))

        # Live readouts
        self.lbl_pos = self._readout(f, 'Current angle', '#89dceb')
        self.lbl_err = self._readout(f, 'Error',         '#f38ba8')

        tk.Frame(f, bg='#44445a', height=1).pack(fill='x', padx=14, pady=14)

        # Sliders
        self._slider_row(f, 'Target angle (°)', self.var_sp,
                         -360, 360, 1.0,   'setpoint', '#fab387')
        self._slider_row(f, 'Kp (proportional)', self.var_kp,
                         0.0,  20.0, 0.1,  'kp',       '#a6e3a1')
        self._slider_row(f, 'Kd (derivative)',   self.var_kd,
                         0.0,   2.0, 0.01, 'kd',       '#cba6f7')

        tk.Frame(f, bg='#44445a', height=1).pack(fill='x', padx=14, pady=14)

        # Buttons
        btn_frame = tk.Frame(f, bg='#2a2a3e')
        btn_frame.pack(fill='x', padx=14, pady=4)

        self._btn(btn_frame, 'Send all', self._send_all, '#89b4fa').pack(
            fill='x', padx=0, pady=3)
        self._btn(btn_frame, 'Reset encoder', self._reset_encoder,
                  '#f38ba8').pack(fill='x', padx=0, pady=3)
        self._btn(btn_frame, 'Clear plot', self._clear_plot,
                  '#6c7086').pack(fill='x', padx=0, pady=3)

        # Status bar
        self.status_var = tk.StringVar(value='Ready')
        tk.Label(f, textvariable=self.status_var, bg='#2a2a3e',
                 fg='#6c7086', font=('', 8), anchor='w').pack(
            side='bottom', fill='x', padx=14, pady=8)

    def _readout(self, parent, label, color):
        """A labeled live-value display."""
        frame = tk.Frame(parent, bg='#2a2a3e')
        frame.pack(fill='x', padx=14, pady=3)
        tk.Label(frame, text=label + ':', bg='#2a2a3e',
                 fg='#6c7086', font=('', 9), width=14,
                 anchor='w').pack(side='left')
        lbl = tk.Label(frame, text='—', bg='#2a2a3e',
                       fg=color, font=('', 11, 'bold'), anchor='e')
        lbl.pack(side='right')
        return lbl

    def _slider_row(self, parent, label, var, from_, to, res, topic, color):
        frame = tk.Frame(parent, bg='#2a2a3e')
        frame.pack(fill='x', padx=14, pady=6)

        tk.Label(frame, text=label, bg='#2a2a3e', fg='#cdd6f4',
                 font=('', 9), anchor='w').pack(fill='x')

        inner = tk.Frame(frame, bg='#2a2a3e')
        inner.pack(fill='x')

        slider = tk.Scale(inner, from_=from_, to=to, variable=var,
                          orient='horizontal', resolution=res,
                          bg='#2a2a3e', fg='#cdd6f4',
                          troughcolor='#313244',
                          highlightthickness=0, showvalue=False,
                          command=lambda v, t=topic: self.node.send(t, float(v)))
        slider.pack(side='left', fill='x', expand=True)

        entry = tk.Entry(inner, textvariable=var, width=7,
                         bg='#313244', fg=color,
                         insertbackground='#cdd6f4',
                         relief='flat', font=('', 9))
        entry.pack(side='left', padx=(6, 0))
        entry.bind('<Return>', lambda e, t=topic: self.node.send(t, var.get()))

    def _btn(self, parent, text, cmd, color):
        return tk.Button(parent, text=text, command=cmd,
                         bg=color, fg='#1e1e2e',
                         activebackground=color, activeforeground='#1e1e2e',
                         font=('', 9, 'bold'), relief='flat',
                         cursor='hand2', pady=6)

    # ── Actions ──────────────────────────────────────────────────────
    def _send_all(self):
        self.node.send('setpoint', self.var_sp.get())
        self.node.send('kp',       self.var_kp.get())
        self.node.send('kd',       self.var_kd.get())
        self.status_var.set(
            f'Sent → sp={self.var_sp.get():.1f}°  '
            f'Kp={self.var_kp.get():.2f}  Kd={self.var_kd.get():.3f}')

    def _reset_encoder(self):
        self.node.send('setpoint', 0.0)
        self.var_sp.set(0.0)
        self.status_var.set('Encoder reset to 0°')

    def _clear_plot(self):
        with self.node._lock:
            self.node.times.clear()
            self.node.positions.clear()
            self.node.setpoints.clear()
            self.node.start_time = time.time()
        self.status_var.set('Plot cleared')

    # ── Animation ────────────────────────────────────────────────────
    def _start_animation(self):
        self.ani = FuncAnimation(
            self.fig, self._update_plot,
            interval=80,   # ~12 fps is plenty for a motor plot
            blit=False,    # blit=False needed for ax.relim()
            cache_frame_data=False
        )

    def _update_plot(self, _):
        with self.node._lock:
            t   = list(self.node.times)
            pos = list(self.node.positions)
            sp  = list(self.node.setpoints)

        if not t:
            return

        errors = [s - p for s, p in zip(sp, pos)]

        self.line_pos.set_data(t, pos)
        self.line_sp.set_data(t, sp)
        self.line_err.set_data(t, errors)

        for ax in (self.ax, self.ax2):
            ax.relim()
            ax.autoscale_view()

        # Live readout labels
        cur_pos = pos[-1] if pos else 0.0
        cur_err = errors[-1] if errors else 0.0
        self.lbl_pos.config(text=f'{cur_pos:+.2f}°')
        self.lbl_err.config(text=f'{cur_err:+.2f}°')

        self.canvas.draw_idle()

    # ── Run ──────────────────────────────────────────────────────────
    def run(self):
        self.root.mainloop()


def main():
    rclpy.init()
    node = MotorControlNode()

    spin_thread = threading.Thread(target=rclpy.spin, args=(node,), daemon=True)
    spin_thread.start()

    app = App(node)
    app.run()

    rclpy.shutdown()


if __name__ == '__main__':
    main()