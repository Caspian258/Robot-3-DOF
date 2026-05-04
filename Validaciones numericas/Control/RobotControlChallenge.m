%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%  Three DOF Non-Planar Revolute Robot Manipulator
%  Parameters extracted from RobotController.m
%
%  Joint layout:
%   Joint 1 – yaw   (rotates about world Z, vertical axis)  BASE
%   Joint 2 – pitch (rotates about local Y, horizontal)     SHOULDER
%   Joint 3 – pitch (rotates about local Y, horizontal)     ELBOW
%
%  Stability note:
%   Forward Euler requires h small enough so that h * max_eigenvalue < 2.
%   With the real robot inertias (~1e-4 kg·m²) and Kp=5, Kd=0.5 the
%   dominant closed-loop pole magnitude is ~230 rad/s, requiring h < 8e-3.
%   We use h = 1e-4 for a comfortable safety margin.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
clc; clear all; close all;

%% ── Physical parameters (from robotParams / robotDynParams) ─────────────

% Link lengths [m]
L1  = 0.100;
L2  = 0.205;
L3  = 0.16569;

% Centre-of-mass distances [m]
lc2 = 0.0114;
lc3 = 0.0237;

% Masses [kg]
M1  = 0.3331;
M2  = 0.3332;
M3  = 0.0548;

% Moments of inertia [kg·m²]
I1z = 0.000922;
I2x = 0.001318;
I2y = 0.000898;
I2z = 0.000983;
I3x = 0.000039;
I3y = 0.000160;
I3z = 0.000131;

% Gravity [m/s²]
grav = 9.81;

%% ── Simulation time ──────────────────────────────────────────────────────
t0 = 0;
tf = 25;
h  = 8e-5;                          % smaller step → numerically stable
N  = round((tf - t0) / h) + 1;     % 500 001 points

%% ── Initial conditions ───────────────────────────────────────────────────
% Robot homes to [0 0 0] deg.  State: [q1;dq1;q2;dq2;q3;dq3]
IC = zeros(6,1);

%% ── Inertia matrix M(q) ──────────────────────────────────────────────────
% Mirrors D matrix in computeSRC() of RobotController.m exactly.
% S(1)=q1, S(3)=q2, S(5)=q3

m11_h = @(S) I1z ...
    + M2*lc2^2*cos(S(3))^2 ...
    + I2x*sin(S(3))^2 + I2y*cos(S(3))^2 ...
    + M3*(L2*cos(S(3)) + lc3*cos(S(3)+S(5)))^2 ...
    + I3x*sin(S(3)+S(5))^2 + I3y*cos(S(3)+S(5))^2;

m12_h = @(S) 0;   m13_h = @(S) 0;
m21_h = @(S) 0;   m31_h = @(S) 0;

m22_h = @(S) M2*lc2^2 + I2z ...
    + M3*(L2^2 + lc3^2 + 2*L2*lc3*cos(S(5))) + I3z;

m23_h = @(S) M3*(lc3^2 + L2*lc3*cos(S(5))) + I3z;
m32_h = @(S) M3*(lc3^2 + L2*lc3*cos(S(5))) + I3z;   % = m23_h by symmetry

m33_h = @(S) M3*lc3^2 + I3z;

%% ── Coriolis / centripetal matrix C(q,dq) ───────────────────────────────
c11_h = @(S) 0;

c12_h = @(S) (-M2*lc2^2*sin(S(3))*cos(S(3)) ...
              +(I2x-I2y)*sin(S(3))*cos(S(3)) ...
              -M3*(L2*cos(S(3))+lc3*cos(S(3)+S(5))) ...
                 .*(L2*sin(S(3))+lc3*sin(S(3)+S(5))) ...
              +(I3x-I3y)*sin(S(3)+S(5))*cos(S(3)+S(5))) * S(2);

c13_h = @(S) (-M3*lc3*(L2*cos(S(3))+lc3*cos(S(3)+S(5))) ...
                 .*sin(S(3)+S(5)) ...
              +(I3x-I3y)*sin(S(3)+S(5))*cos(S(3)+S(5))) * S(2);

c21_h = @(S) ( M2*lc2^2*sin(S(3))*cos(S(3)) ...
              -(I2x-I2y)*sin(S(3))*cos(S(3)) ...
              +M3*(L2*cos(S(3))+lc3*cos(S(3)+S(5))) ...
                 .*(L2*sin(S(3))+lc3*sin(S(3)+S(5))) ...
              -(I3x-I3y)*sin(S(3)+S(5))*cos(S(3)+S(5))) * S(2);

c22_h = @(S) -M3*L2*lc3*sin(S(5)) * S(6);
c23_h = @(S) -M3*L2*lc3*sin(S(5)) * (S(4)+S(6));

c31_h = @(S) ( M3*lc3*(L2*cos(S(3))+lc3*cos(S(3)+S(5))) ...
                 .*sin(S(3)+S(5)) ...
              -(I3x-I3y)*sin(S(3)+S(5))*cos(S(3)+S(5))) * S(2);

c32_h = @(S)  M3*L2*lc3*sin(S(5)) * S(4);
c33_h = @(S) 0;

%% ── Gravity vector G(q) ─────────────────────────────────────────────────
% G1=0: Joint 1 is a yaw about vertical Z.
% G2,G3: cos() convention — pitch joints with Z pointing up.
g1_h = @(S) 0;
g2_h = @(S) M2*grav*lc2*cos(S(3)) + M3*grav*(L2*cos(S(3))+lc3*cos(S(3)+S(5)));
g3_h = @(S) M3*grav*lc3*cos(S(3)+S(5));

%% ── Control gains ────────────────────────────────────────────────────────
% Gains are tuned for stability with the real robot inertias.
% Large Kp with very small inertia stiffens the system and requires
% smaller h; these values give smooth responses at h = 1e-4.
%
%   Rule of thumb stability check (simplified 1-DOF):
%     h  <  2*sqrt(I_min / Kp)
%     h  <  2*sqrt(1.31e-4 / 5) ≈ 0.010 s   → h=1e-4 has 100x margin
Kp = 6.0;
Kd = 0.98;

%% ── Numerical integration ────────────────────────────────────────────────
fprintf('Running simulation: N = %d steps (h = %.0e s) ...\n', N, h);
tic
[y_out, tau_out, err_out, t_out] = forwardEuler_RobotControl_3DOF( ...
    m11_h, m12_h, m13_h, ...
    m21_h, m22_h, m23_h, ...
    m31_h, m32_h, m33_h, ...
    c11_h, c12_h, c13_h, ...
    c21_h, c22_h, c23_h, ...
    c31_h, c32_h, c33_h, ...
    g1_h, g2_h, g3_h, ...
    Kp, Kd, t0, tf, IC, h, N);
fprintf('Done in %.1f s\n', toc);

%% ── Downsample for plotting (every 50 steps → 10 000 plot points) ────────
% With h=1e-4 and tf=50 we have 500 001 points. Plotting all of them
% is slow and visually identical to a 10 000-point downsampled version.
ds   = 50;                          % downsample factor
idx  = 1:ds:N;
time = t_out(idx);
q1   = y_out(1,idx);   dq1 = y_out(2,idx);
q2   = y_out(3,idx);   dq2 = y_out(4,idx);
q3   = y_out(5,idx);   dq3 = y_out(6,idx);
tau1 = tau_out(1,idx); tau2 = tau_out(2,idx); tau3 = tau_out(3,idx);
e1   = err_out(1,idx); e2   = err_out(2,idx); e3   = err_out(3,idx);

% Desired trajectory (for overlay on position plots)
w   = pi/10;
A1  = 0.4; A2 = 0.3; A3 = 0.2;
ph2 = pi/4; ph3 = -pi/4;
qd1 = A1*sin(w*time);
qd2 = A2*sin(w*time+ph2);
qd3 = A3*sin(w*time+ph3);

%% ── Figure 1: Joint angles (actual vs desired) ──────────────────────────
figure('Name','Joint Angles')

subplot(3,1,1)
plot(time, rad2deg(q1),  'Color',[0 0.447 0.741], 'LineWidth',1.5); hold on
plot(time, rad2deg(qd1), 'k--', 'LineWidth',1)
xlabel('time (s)'), ylabel('q_1 (deg)')
title('Joint 1 – Yaw (actual vs desired)')
legend('actual','desired','Location','best'), grid on

subplot(3,1,2)
plot(time, rad2deg(q2),  'Color',[0.850 0.325 0.098], 'LineWidth',1.5); hold on
plot(time, rad2deg(qd2), 'k--', 'LineWidth',1)
xlabel('time (s)'), ylabel('q_2 (deg)')
title('Joint 2 – Shoulder (actual vs desired)')
legend('actual','desired','Location','best'), grid on

subplot(3,1,3)
plot(time, rad2deg(q3),  'Color',[0.466 0.674 0.188], 'LineWidth',1.5); hold on
plot(time, rad2deg(qd3), 'k--', 'LineWidth',1)
xlabel('time (s)'), ylabel('q_3 (deg)')
title('Joint 3 – Elbow (actual vs desired)')
legend('actual','desired','Location','best'), grid on

%% ── Figure 2: Joint velocities ───────────────────────────────────────────
figure('Name','Joint Velocities')

subplot(3,1,1)
plot(time, rad2deg(dq1), 'Color',[0 0.447 0.741], 'LineWidth',1.5)
xlabel('time (s)'), ylabel('\dot{q}_1 (deg/s)'), title('Joint 1 Velocity'), grid on

subplot(3,1,2)
plot(time, rad2deg(dq2), 'Color',[0.850 0.325 0.098], 'LineWidth',1.5)
xlabel('time (s)'), ylabel('\dot{q}_2 (deg/s)'), title('Joint 2 Velocity'), grid on

subplot(3,1,3)
plot(time, rad2deg(dq3), 'Color',[0.466 0.674 0.188], 'LineWidth',1.5)
xlabel('time (s)'), ylabel('\dot{q}_3 (deg/s)'), title('Joint 3 Velocity'), grid on

%% ── Figure 3: Torques ────────────────────────────────────────────────────
figure('Name','Joint Torques')

subplot(3,1,1)
plot(time, tau1, 'Color',[0 0.447 0.741], 'LineWidth',1.5)
xlabel('time (s)'), ylabel('\tau_1 (N·m)'), title('Torque 1'), grid on

subplot(3,1,2)
plot(time, tau2, 'Color',[0.850 0.325 0.098], 'LineWidth',1.5)
xlabel('time (s)'), ylabel('\tau_2 (N·m)'), title('Torque 2'), grid on

subplot(3,1,3)
plot(time, tau3, 'Color',[0.466 0.674 0.188], 'LineWidth',1.5)
xlabel('time (s)'), ylabel('\tau_3 (N·m)'), title('Torque 3'), grid on

%% ── Figure 4: Position errors ────────────────────────────────────────────
figure('Name','Position Errors')

subplot(3,1,1)
plot(time, rad2deg(e1), 'Color',[0 0.447 0.741], 'LineWidth',1.5)
xlabel('time (s)'), ylabel('e_1 (deg)'), title('Error 1'), grid on

subplot(3,1,2)
plot(time, rad2deg(e2), 'Color',[0.850 0.325 0.098], 'LineWidth',1.5)
xlabel('time (s)'), ylabel('e_2 (deg)'), title('Error 2'), grid on

subplot(3,1,3)
plot(time, rad2deg(e3), 'Color',[0.466 0.674 0.188], 'LineWidth',1.5)
xlabel('time (s)'), ylabel('e_3 (deg)'), title('Error 3'), grid on

%% ── Figure 5: 3-D Animation ──────────────────────────────────────────────
gifFile = 'robot3DOF_animation.gif';
obj = figure('Name','3-DOF Robot Animation');

subplot(1,2,1)
robotPlot3DOF(IC(1), IC(3), IC(5), L1, L2, L3)
title('3-DOF Non-Planar Robot')

subplot(1,2,2)
plot(time, rad2deg(q1), 'b', ...
     time, rad2deg(q2), 'r', ...
     time, rad2deg(q3), 'g', 'LineWidth',1.5)
legend('q_1','q_2','q_3','Location','best')
xlabel('time (s)'), ylabel('angle (deg)')
title('Joint Trajectories'), grid on

exportgraphics(obj, gifFile);

% Animation loop — step through downsampled index
Nds = numel(time);
for k = 1:ceil(Nds/200):Nds
    clf(obj)

    subplot(1,2,1)
    robotPlot3DOF(q1(k), q2(k), q3(k), L1, L2, L3)
    title(sprintf('t = %.2f s', time(k)))

    subplot(1,2,2)
    plot(time, rad2deg(q1), 'b', ...
         time, rad2deg(q2), 'r', ...
         time, rad2deg(q3), 'g', 'LineWidth',1.5)
    hold on
    plot(time(k), rad2deg(q1(k)), 'ob','MarkerSize',8,'MarkerFaceColor','b')
    plot(time(k), rad2deg(q2(k)), 'or','MarkerSize',8,'MarkerFaceColor','r')
    plot(time(k), rad2deg(q3(k)), 'og','MarkerSize',8,'MarkerFaceColor','g')
    legend('q_1','q_2','q_3','Location','best')
    xlabel('time (s)'), ylabel('angle (deg)')
    title('Joint Trajectories'), grid on

    exportgraphics(obj, gifFile, 'Append', true)
end