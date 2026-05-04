function [y, tau, error_out, t] = forwardEuler_RobotControl_3DOF( ...
    M11, M12, M13, M21, M22, M23, M31, M32, M33, ...
    C11, C12, C13, C21, C22, C23, C31, C32, C33, ...
    G1,  G2,  G3,  KP,  KD,  t0,  T,   y0,  h,  N)
% ============================================================
%  Forward Euler integrator — 3-DOF non-planar revolute arm
%
%  State vector (6x1):
%    S(1)=q1   S(2)=dq1   Joint 1 – yaw   (base)
%    S(3)=q2   S(4)=dq2   Joint 2 – pitch (shoulder)
%    S(5)=q3   S(6)=dq3   Joint 3 – pitch (elbow)
%
%  Control law — Computed-Torque PD:
%    u = M(q)*(ddqd - Kp*e - Kd*de) + C(q,dq)*dq + G(q)
%
%  NOTE ON STABILITY:
%    Forward Euler is conditionally stable.  With the small inertias
%    of the real robot (I3z ~ 1.3e-4 kg·m²) the closed-loop
%    eigenvalues are large, so h must be small (≤ 1e-4 s).
%    The main script sets h = 1e-4 and N accordingly.
%
%  Inputs
%    Mij     function handles (or scalars) for inertia matrix entries
%    Cij     function handles (or scalars) for Coriolis matrix entries
%    Gi      function handles for gravity vector entries
%    KP, KD  scalar proportional / derivative gains
%    t0, T   initial and final time [s]
%    y0      6x1 initial state [q1;dq1;q2;dq2;q3;dq3]
%    h       time step [s]   — use 1e-4 for stability
%    N       number of time points (linspace gives N points,
%            loop runs N-1 Euler steps each of size h)
%
%  Outputs
%    y           6xN  state trajectory
%    tau         3xN  joint torque history   [N·m]
%    error_out   3xN  position error         [rad]   (q - qd)
%    t           1xN  time vector            [s]
% ============================================================

% ── Allocate ─────────────────────────────────────────────────────────────
t         = linspace(t0, T, N);
y         = zeros(6, N);
y(:,1)    = y0(:);
tau       = zeros(3, N);
error_out = zeros(3, N);

% ── Gain matrices ─────────────────────────────────────────────────────────
KPmat = KP * eye(3);
KDmat = KD * eye(3);

% ── Reference trajectory ──────────────────────────────────────────────────
% Small-amplitude sinusoids so joints stay within ±30 deg,
% which matches the physical robot's operating range.
%   q1_d =  0.4*sin(w*t)          yaw
%   q2_d =  0.3*sin(w*t + pi/4)   shoulder pitch
%   q3_d =  0.2*sin(w*t - pi/4)   elbow pitch
A1 = 0.4;  A2 = 0.3;  A3 = 0.2;   % amplitudes [rad]
ph2 =  pi/4;                        % phase shoulder
ph3 = -pi/4;                        % phase elbow
w   = pi/10;                        % frequency  [rad/s]  → period 20 s

% ── Permutation matrix ────────────────────────────────────────────────────
% Maps [dq; ddq] (6x1) → interleaved state order [dq1;ddq1;dq2;ddq2;dq3;ddq3]
PM = [1 0 0 0 0 0; ...
      0 0 0 1 0 0; ...
      0 1 0 0 0 0; ...
      0 0 0 0 1 0; ...
      0 0 1 0 0 0; ...
      0 0 0 0 0 1];

% ============================================================
%  Main loop
% ============================================================
for i = 1:(N-1)

    ti = t(i);

    % ── Desired trajectory ──────────────────────────────────
    qd   = [ A1* sin(w*ti);           A2* sin(w*ti+ph2);           A3* sin(w*ti+ph3)           ];
    dqd  = [ A1*w*cos(w*ti);          A2*w*cos(w*ti+ph2);          A3*w*cos(w*ti+ph3)          ];
    ddqd = [-A1*w^2*sin(w*ti);       -A2*w^2*sin(w*ti+ph2);       -A3*w^2*sin(w*ti+ph3)       ];

    % ── Unpack current state ────────────────────────────────
    S  = y(:,i);
    q  = [S(1); S(3); S(5)];
    dq = [S(2); S(4); S(6)];

    % ── Build M, C, G at current state ─────────────────────
    Mmat = [M11(S) M12(S) M13(S); ...
            M21(S) M22(S) M23(S); ...
            M31(S) M32(S) M33(S)];

    Cmat = [C11(S) C12(S) C13(S); ...
            C21(S) C22(S) C23(S); ...
            C31(S) C32(S) C33(S)];

    Gvec = [G1(S); G2(S); G3(S)];

    % ── Computed-torque PD law ──────────────────────────────
    e_pos = q  - qd;
    e_vel = dq - dqd;

    u = Mmat*(ddqd - KPmat*e_pos - KDmat*e_vel) + Cmat*dq + Gvec;

    % ── Equations of motion   ddq = M \ (u - C*dq - G) ────
    ddq = Mmat \ (u - Cmat*dq - Gvec);

    % ── Forward Euler update ────────────────────────────────
    f        = [dq; ddq];
    y(:,i+1) = y(:,i) + h * PM * f;

    % ── Store outputs ───────────────────────────────────────
    tau(:,i)       = u;
    error_out(:,i) = e_pos;
end

% ── Last column (hold previous, fill final error) ────────────────────────
tN            = t(N);
S_end         = y(:,N);
q_end         = [S_end(1); S_end(3); S_end(5)];
qd_end        = [A1*sin(w*tN); A2*sin(w*tN+ph2); A3*sin(w*tN+ph3)];
tau(:,N)      = tau(:,N-1);
error_out(:,N)= q_end - qd_end;

end