#!/usr/bin/env python3
"""
pd_gui_node.py — 3-motor PD controller GUI.
Topics per motor : motor/m<n>/setpoint, motor/m<n>/position  (n = 1, 2, 3)
Shared gain topics: motor/kp, motor/kd
"""
import threading, time
import tkinter as tk
from tkinter import ttk
import numpy as np

import matplotlib
matplotlib.use('TkAgg')
import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from matplotlib.animation import FuncAnimation
import matplotlib.gridspec as gridspec

import rclpy
from rclpy.node import Node
from std_msgs.msg import Float64

NUM_MOTORS = 3
COLORS_POS = ['#89dceb', '#a6e3a1', '#cba6f7']
COLORS_SP  = ['#fab387', '#f9e2af', '#f38ba8']
BG_DARK    = '#1e1e2e'
BG_MID     = '#2a2a3e'
BG_PANEL   = '#313244'
FG_TEXT    = '#cdd6f4'
FG_DIM     = '#6c7086'
ACCENT     = '#89b4fa'


# ──────────────────────────────────────────────────────────────────────────────
class MotorControlNode(Node):
    def __init__(self):
        super().__init__('motor_pd_gui_node')

        self.pub_sp = [self.create_publisher(Float64, f'motor/m{i+1}/setpoint', 10)
                       for i in range(NUM_MOTORS)]
        self.pub_kp = self.create_publisher(Float64, 'motor/kp', 10)
        self.pub_kd = self.create_publisher(Float64, 'motor/kd', 10)

        for i in range(NUM_MOTORS):
            self.create_subscription(Float64, f'motor/m{i+1}/position',
                                     self._make_pos_cb(i), 10)
            self.create_subscription(Float64, f'motor/m{i+1}/setpoint',
                                     self._make_sp_cb(i), 10)

        self._lock = threading.Lock()
        self.t0    = time.time()

        self.times     = [[] for _ in range(NUM_MOTORS)]
        self.positions = [[] for _ in range(NUM_MOTORS)]
        self.setpoints = [[] for _ in range(NUM_MOTORS)]
        self.cur_pos   = [0.0] * NUM_MOTORS
        self.cur_sp    = [0.0] * NUM_MOTORS

    def _make_pos_cb(self, idx):
        def cb(msg):
            with self._lock:
                t = time.time() - self.t0
                self.times[idx].append(t)
                self.positions[idx].append(msg.data)
                self.setpoints[idx].append(self.cur_sp[idx])
                self.cur_pos[idx] = msg.data
                if len(self.times[idx]) > 500:
                    self.times[idx].pop(0)
                    self.positions[idx].pop(0)
                    self.setpoints[idx].pop(0)
        return cb

    def _make_sp_cb(self, idx):
        def cb(msg):
            self.cur_sp[idx] = msg.data
        return cb

    def send_setpoint(self, idx, val):
        m = Float64()
        m.data = float(val)
        self.pub_sp[idx].publish(m)

    def send_gain(self, topic, val):
        m = Float64()
        m.data = float(val)
        (self.pub_kp if topic == 'kp' else self.pub_kd).publish(m)
        self.get_logger().info(f'[{topic}] → {val:.4f}')


# ──────────────────────────────────────────────────────────────────────────────
class App:
    def __init__(self, node: MotorControlNode):
        self.node = node

        self.root = tk.Tk()
        self.root.title('Motor PD Controller — 3 motors')
        self.root.configure(bg=BG_DARK)
        self.root.geometry('1200x750')
        self.root.minsize(900, 650)

        self.var_kp = tk.DoubleVar(value=3.0)
        self.var_kd = tk.DoubleVar(value=0.49)
        self.var_sp = [tk.DoubleVar(value=0.0) for _ in range(NUM_MOTORS)]

        self._build_ui()
        self._start_animation()

    # ── Top-level layout ──────────────────────────────────────────────────────
    def _build_ui(self):
        self.root.columnconfigure(0, weight=3)
        self.root.columnconfigure(1, weight=1, minsize=270)
        self.root.rowconfigure(0, weight=1)

        left = tk.Frame(self.root, bg=BG_DARK)
        left.grid(row=0, column=0, sticky='nsew', padx=(10, 4), pady=10)
        left.rowconfigure(0, weight=1)
        left.columnconfigure(0, weight=1)

        style = ttk.Style()
        style.theme_use('clam')
        style.configure('Dark.TNotebook',     background=BG_DARK, borderwidth=0)
        style.configure('Dark.TNotebook.Tab', background=BG_MID,
                        foreground=FG_TEXT,   padding=[10, 4])
        style.map('Dark.TNotebook.Tab',
                  background=[('selected', BG_PANEL)],
                  foreground=[('selected', ACCENT)])

        self.notebook = ttk.Notebook(left, style='Dark.TNotebook')
        self.notebook.grid(sticky='nsew')

        self.figs     = []
        self.canvases = []
        self.axes     = []
        self.lines    = []

        for i in range(NUM_MOTORS):
            frame = tk.Frame(self.notebook, bg=BG_DARK)
            self.notebook.add(frame, text=f' Motor {i+1} ')
            self._build_motor_plot(frame, i)

        right = tk.Frame(self.root, bg=BG_MID,
                         highlightbackground='#44445a', highlightthickness=1)
        right.grid(row=0, column=1, sticky='nsew', padx=(4, 10), pady=10)
        self._build_controls(right)

    # ── Per-motor plot ────────────────────────────────────────────────────────
    def _build_motor_plot(self, parent, idx):
        fig = plt.Figure(figsize=(6, 4.5), dpi=100)
        fig.patch.set_facecolor(BG_DARK)
        gs  = gridspec.GridSpec(2, 1, figure=fig,
                                height_ratios=[3, 1], hspace=0.4)

        c_pos = COLORS_POS[idx]
        c_sp  = COLORS_SP[idx]

        ax = fig.add_subplot(gs[0])
        ax.set_facecolor('#12121f')
        ax.set_title(f'Motor {idx+1} — Angular position',
                     color=FG_TEXT, fontsize=10, pad=6)
        ax.set_xlabel('Time (s)', color=FG_DIM, fontsize=8)
        ax.set_ylabel('Angle (°)', color=FG_DIM, fontsize=8)
        ax.tick_params(colors=FG_DIM, labelsize=7)
        for sp in ax.spines.values():
            sp.set_edgecolor('#44445a')
        ax.grid(True, color='#313244', linewidth=0.5)

        lp, = ax.plot([], [], color=c_pos, linewidth=1.8, label='Position')
        ls, = ax.plot([], [], color=c_sp,  linewidth=1.4,
                      linestyle='--', label='Setpoint')
        ax.legend(loc='upper right', fontsize=7, facecolor=BG_MID,
                  edgecolor='#44445a', labelcolor=FG_TEXT)

        ax2 = fig.add_subplot(gs[1])
        ax2.set_facecolor('#12121f')
        ax2.set_title('Error', color=FG_TEXT, fontsize=9, pad=4)
        ax2.set_xlabel('Time (s)', color=FG_DIM, fontsize=8)
        ax2.set_ylabel('Error (°)', color=FG_DIM, fontsize=8)
        ax2.tick_params(colors=FG_DIM, labelsize=7)
        for sp in ax2.spines.values():
            sp.set_edgecolor('#44445a')
        ax2.grid(True, color='#313244', linewidth=0.5)
        ax2.axhline(0, color='#585b70', linewidth=0.8)

        le, = ax2.plot([], [], color='#f38ba8', linewidth=1.4)

        canvas = FigureCanvasTkAgg(fig, master=parent)
        canvas.get_tk_widget().pack(fill='both', expand=True)

        self.figs.append(fig)
        self.canvases.append(canvas)
        self.axes.append((ax, ax2))
        self.lines.append((lp, ls, le))

    # ── Right-panel controls ──────────────────────────────────────────────────
    def _build_controls(self, f):
        tk.Label(f, text='PD Controller', bg=BG_MID,
                 fg=FG_TEXT, font=('', 13, 'bold')).pack(pady=(18, 10))

        self.lbl_pos = []
        self.lbl_err = []
        for i in range(NUM_MOTORS):
            row = tk.Frame(f, bg=BG_MID)
            row.pack(fill='x', padx=14, pady=2)
            tk.Label(row, text=f'M{i+1} pos:', bg=BG_MID, fg=FG_DIM,
                     font=('', 8), width=7, anchor='w').pack(side='left')
            lp = tk.Label(row, text='—', bg=BG_MID, fg=COLORS_POS[i],
                          font=('', 10, 'bold'), anchor='e')
            lp.pack(side='left', padx=(0, 12))
            tk.Label(row, text='err:', bg=BG_MID, fg=FG_DIM,
                     font=('', 8), anchor='w').pack(side='left')
            le = tk.Label(row, text='—', bg=BG_MID, fg='#f38ba8',
                          font=('', 10, 'bold'), anchor='e')
            le.pack(side='left')
            self.lbl_pos.append(lp)
            self.lbl_err.append(le)

        tk.Frame(f, bg='#44445a', height=1).pack(fill='x', padx=14, pady=10)

        tk.Label(f, text='Setpoints', bg=BG_MID,
                 fg=FG_DIM, font=('', 9)).pack(anchor='w', padx=14)
        for i in range(NUM_MOTORS):
            self._slider_row(f, f'Motor {i+1} target (°)', self.var_sp[i],
                             -360, 360, 1.0, COLORS_SP[i],
                             lambda v, idx=i: self.node.send_setpoint(idx, float(v)))

        tk.Frame(f, bg='#44445a', height=1).pack(fill='x', padx=14, pady=10)

        tk.Label(f, text='Shared gains', bg=BG_MID,
                 fg=FG_DIM, font=('', 9)).pack(anchor='w', padx=14)
        self._slider_row(f, 'Kp (proportional)', self.var_kp,
                         0.0, 20.0, 0.1, '#a6e3a1',
                         lambda v: self.node.send_gain('kp', float(v)))
        self._slider_row(f, 'Kd (derivative)', self.var_kd,
                         0.0, 10.0, 0.01, '#cba6f7',
                         lambda v: self.node.send_gain('kd', float(v)))

        tk.Frame(f, bg='#44445a', height=1).pack(fill='x', padx=14, pady=10)

        btn_f = tk.Frame(f, bg=BG_MID)
        btn_f.pack(fill='x', padx=14)
        self._btn(btn_f, 'Send all',         self._send_all,   ACCENT    ).pack(fill='x', pady=3)
        self._btn(btn_f, 'Zero all setpoints', self._zero_all, '#f38ba8' ).pack(fill='x', pady=3)
        self._btn(btn_f, 'Clear plots',      self._clear_plots, FG_DIM   ).pack(fill='x', pady=3)
        
        # [NEW] Calculate A and B using Least Squares Regression
        self._btn(btn_f, 'Calculate A & B (Least Squares)', self._calc_ab, '#a6e3a1').pack(fill='x', pady=3)

        self.status_var = tk.StringVar(value='Ready')
        tk.Label(f, textvariable=self.status_var, bg=BG_MID, fg=FG_DIM,
                 font=('', 7), anchor='w', wraplength=240).pack(side='bottom', fill='x',
                                                padx=14, pady=6)

    def _slider_row(self, parent, label, var, lo, hi, res, color, cmd):
        frame = tk.Frame(parent, bg=BG_MID)
        frame.pack(fill='x', padx=14, pady=4)
        tk.Label(frame, text=label, bg=BG_MID, fg=FG_TEXT,
                 font=('', 8), anchor='w').pack(fill='x')
        inner = tk.Frame(frame, bg=BG_MID)
        inner.pack(fill='x')
        tk.Scale(inner, from_=lo, to=hi, variable=var,
                 orient='horizontal', resolution=res,
                 bg=BG_MID, fg=FG_TEXT, troughcolor=BG_PANEL,
                 highlightthickness=0, showvalue=False,
                 command=cmd).pack(side='left', fill='x', expand=True)
        tk.Entry(inner, textvariable=var, width=6, bg=BG_PANEL, fg=color,
                 insertbackground=FG_TEXT, relief='flat',
                 font=('', 8)).pack(side='left', padx=(4, 0))

    def _btn(self, parent, text, cmd, color):
        return tk.Button(parent, text=text, command=cmd,
                         bg=color, fg=BG_DARK,
                         activebackground=color, font=('', 8, 'bold'),
                         relief='flat', cursor='hand2', pady=5)

    # ── Actions ───────────────────────────────────────────────────────────────
    def _send_all(self):
        for i in range(NUM_MOTORS):
            self.node.send_setpoint(i, self.var_sp[i].get())
        self.node.send_gain('kp', self.var_kp.get())
        self.node.send_gain('kd', self.var_kd.get())
        self.status_var.set(
            f'Sent all — Kp={self.var_kp.get():.2f} Kd={self.var_kd.get():.3f}')

    def _zero_all(self):
        for i in range(NUM_MOTORS):
            self.var_sp[i].set(0.0)
            self.node.send_setpoint(i, 0.0)
        self.status_var.set('All setpoints → 0°')

    def _clear_plots(self):
        with self.node._lock:
            for i in range(NUM_MOTORS):
                self.node.times[i].clear()
                self.node.positions[i].clear()
                self.node.setpoints[i].clear()
            self.node.t0 = time.time()
        self.status_var.set('Plots cleared')

    def _calc_ab(self):
        kp = self.var_kp.get()
        kd = self.var_kd.get()
        results = []
        
        with self.node._lock:
            for i in range(NUM_MOTORS):
                t = np.array(self.node.times[i])
                pos = np.array(self.node.positions[i])
                sp = np.array(self.node.setpoints[i])
                
                if len(t) < 50:
                    results.append(f"M{i+1}: Need more data")
                    continue
                
                dt = np.diff(t)
                dt[dt == 0] = 0.001 
                
                vel = np.diff(pos) / dt
                vel = np.concatenate(([0.0], vel))
                
                acc = np.diff(vel) / dt
                acc = np.concatenate(([0.0], acc))
                
                err = sp - pos
                err_diff = np.diff(err) / dt
                err_diff = np.concatenate(([0.0], err_diff))
                
                # Reconstruct the PD PWM output (u) based on known gains
                u = (kp * err) + (kd * err_diff)
                
                # Least Squares Regression: u = A*acc + B*vel
                X = np.vstack([acc, vel]).T
                Y = u
                
                ab, residuals, rank, s = np.linalg.lstsq(X, Y, rcond=None)
                A, B = ab[0], ab[1]
                results.append(f"M{i+1} [A:{A:.3f} B:{B:.3f}]")

        res_str = " | ".join(results)
        self.status_var.set(f"Calc: {res_str}")
        self.node.get_logger().info(res_str)

    # ── Animation — one per figure, closure binds correct motor index ─────────
    def _start_animation(self):
        self.anis = [
            FuncAnimation(
                self.figs[i], self._make_update(i),
                interval=200, blit=False, cache_frame_data=False
            )
            for i in range(NUM_MOTORS)
        ]

    def _make_update(self, idx):
        def _update(_):
            with self.node._lock:
                t   = list(self.node.times[idx])
                pos = list(self.node.positions[idx])
                sp  = list(self.node.setpoints[idx])

            if not t:
                return

            errors = [s - p for s, p in zip(sp, pos)]

            lp, ls, le = self.lines[idx]
            lp.set_data(t, pos)
            ls.set_data(t, sp)
            le.set_data(t, errors)

            for ax in self.axes[idx]:
                ax.relim()
                ax.autoscale_view()

            self.canvases[idx].draw_idle()

            self.lbl_pos[idx].config(text=f'{pos[-1]:+.1f}°')
            self.lbl_err[idx].config(text=f'{errors[-1]:+.1f}°')

        return _update

    # ── Run ───────────────────────────────────────────────────────────────────
    def run(self):
        self.root.mainloop()


# ──────────────────────────────────────────────────────────────────────────────
def main():
    rclpy.init()
    node = MotorControlNode()
    threading.Thread(target=rclpy.spin, args=(node,), daemon=True).start()
    App(node).run()
    rclpy.shutdown()


if __name__ == '__main__':
    main()