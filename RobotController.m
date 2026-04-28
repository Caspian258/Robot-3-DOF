% ============================================================
%  RobotController.m – Robot RRR 3DOF | GUI
% ============================================================
clear; clc; close all;
p = robotParams();
robotGUI(p);

% ============================================================
function robotGUI(p)

cBg         = [0.05 0.07 0.10];
cPanel      = [0.10 0.12 0.16];
cPanel2     = [0.13 0.16 0.21];
cAccent     = [0.15 0.75 0.85];
cWarn       = [1.00 0.60 0.10];
cOk         = [0.20 0.85 0.40];
cRed        = [1.00 0.30 0.30];
cPurple     = [0.70 0.40 0.90];
motorColors = {cAccent, cOk, cWarn};
motorNames  = {'M1 (Base)', 'M2 (Hombro)', 'M3 (Codo)'};

% ── Estado como AppData de la figura (evita problema de closure con structs) ──
% Se usa getappdata/setappdata para que configureCallback vea siempre
% la versión más reciente del estado.
initState = struct(...
  'port',      [], ...
  'connected', false, ...
  'target_q',  [0 45 -45], ...
  'current_q', [0 0 0], ...
  'pwm',       [0 0 0], ...
  'time',      [], ...
  'data_q',    zeros(3,0), ...
  'data_e',    zeros(3,0), ...
  'data_pwm',  zeros(3,0), ...
  't0',        0, ...
  'testMode',  false ...
);

% ── FIGURA ──
fig = uifigure('Name','Robot RRR 3DOF — Control PD', 'Color', cBg);
fig.Position(3:4) = [1400 840];
setappdata(fig,'st', initState);

mainGrid = uigridlayout(fig, [2,2]);
mainGrid.ColumnWidth   = {390,'1x'};
mainGrid.RowHeight     = {'1x', 280};
mainGrid.Padding       = [6 6 6 6];
mainGrid.RowSpacing    = 6;
mainGrid.ColumnSpacing = 6;

% ── PANEL IZQUIERDO ──
pnl = uipanel(mainGrid,'BackgroundColor',cPanel,'BorderType','none');
pnl.Layout.Row=[1 2]; pnl.Layout.Column=1;
pg = uigridlayout(pnl,[1,1]); pg.Padding=[8 8 8 8];

pnlScroll = uigridlayout(pg,[20,1]);
pnlScroll.RowHeight = {22,36,44,8, 22,36,36,36, 44,8, 22,36, 8, 22,44, 8,44,8,22,120};
pnlScroll.RowSpacing = 4;

% DESTINO
mkLabel(pnlScroll,'▸ DESTINO (mm)', 14, cAccent);
gXYZ = uigridlayout(pnlScroll,[1,6]); gXYZ.Padding=[0 0 0 0]; gXYZ.ColumnSpacing=4;
uilabel(gXYZ,'Text','X','FontColor','w','HorizontalAlignment','right');
efX = mkEdit(gXYZ, 200);
uilabel(gXYZ,'Text','Y','FontColor','w','HorizontalAlignment','right');
efY = mkEdit(gXYZ, 0);
uilabel(gXYZ,'Text','Z','FontColor','w','HorizontalAlignment','right');
efZ = mkEdit(gXYZ, 150);
btnGo = uibutton(pnlScroll,'push','Text','⟶  EJECUTAR TRAYECTORIA',...
  'BackgroundColor',cAccent,'FontWeight','bold','FontColor',[0 0 0]);
uilabel(pnlScroll,'Text','');

% GANANCIAS PD
mkLabel(pnlScroll,'▸ GANANCIAS PD', 14, cWarn);
[efP1,efD1] = motorRow(pnlScroll,'M1 Base  ', motorColors{1}, 2.0, 0.05);
[efP2,efD2] = motorRow(pnlScroll,'M2 Hombro', motorColors{2}, 2.5, 0.05);
[efP3,efD3] = motorRow(pnlScroll,'M3 Codo  ', motorColors{3}, 2.5, 0.05);
btnPD = uibutton(pnlScroll,'push','Text','↻  ACTUALIZAR GANANCIAS',...
  'BackgroundColor',cWarn,'FontWeight','bold','FontColor',[0 0 0]);
uilabel(pnlScroll,'Text','');

% ZONA MUERTA
mkLabel(pnlScroll,'▸ ZONA MUERTA (°)', 13, [0.7 0.5 0.9]);
gDB = uigridlayout(pnlScroll,[1,6]); gDB.Padding=[0 0 0 0]; gDB.ColumnSpacing=4;
uilabel(gDB,'Text','M1','FontColor','w'); efDB1 = mkEdit(gDB, 5.0);
uilabel(gDB,'Text','M2','FontColor','w'); efDB2 = mkEdit(gDB, 5.0);
uilabel(gDB,'Text','M3','FontColor','w'); efDB3 = mkEdit(gDB, 5.0);
uilabel(pnlScroll,'Text','');

% TEST DE MOTORES
mkLabel(pnlScroll,'▸ TEST MOTORES', 13, cPurple);
btnTest = uibutton(pnlScroll,'push',...
  'Text','▶  VERIFICAR LOS 3 MOTORES',...
  'BackgroundColor',cPurple,'FontWeight','bold','FontColor','w');
uilabel(pnlScroll,'Text','');

% CONEXIÓN
gSerial = uigridlayout(pnlScroll,[1,3]); gSerial.Padding=[0 0 0 0]; gSerial.ColumnSpacing=4;
ddPort     = uidropdown(gSerial,'Items',serialportlist("available"),...
               'BackgroundColor',cPanel2,'FontColor','w');
btnConnect = uibutton(gSerial,'push','Text','CONECTAR',...
               'BackgroundColor',[0.2 0.5 0.8],'FontColor','w');
btnZero    = uibutton(gSerial,'push','Text','ZERO',...
               'BackgroundColor',[0.5 0.2 0.2],'FontColor','w');
uilabel(pnlScroll,'Text','');
mkLabel(pnlScroll,'▸ LOG', 11, [0.5 0.5 0.5]);
txtLog = uitextarea(pnlScroll,'BackgroundColor',[0 0 0],...
  'FontColor',[0 0.9 0.3],'Editable',false,'FontSize',10);

% ── AXES 3D ──
ax3D = uiaxes(mainGrid,'Color',cBg);
ax3D.Layout.Row=1; ax3D.Layout.Column=2;
estilo3D(ax3D,'Modelo 3D  |  Arrastrar=Rotar   Shift+Click=Mover');
disableDefaultInteractivity(ax3D);
ax3D.ButtonDownFcn = @(src,~) iniciarInteraccion(src);

% ── PANEL GRÁFICAS ──
pnlGraf = uipanel(mainGrid,'BackgroundColor',cPanel,'BorderType','none');
pnlGraf.Layout.Row=2; pnlGraf.Layout.Column=2;
gg = uigridlayout(pnlGraf,[1,2]);
gg.ColumnWidth = {'1x',200}; gg.Padding = [6 6 6 6];

axCtrl = uiaxes(gg,'Color',cBg);
axCtrl.Layout.Row=1; axCtrl.Layout.Column=1;
estiloAx(axCtrl,'Gráfica de Control');

selGrid = uigridlayout(gg,[8,1]);
selGrid.RowHeight={22,30,30,30,8,22,30,8};
mkLabel(selGrid,'SEÑAL',11,cAccent);
cbQ  = uicheckbox(selGrid,'Text','Posición (°)','Value',1,'FontColor','w');
cbE  = uicheckbox(selGrid,'Text','Error (°)',   'Value',0,'FontColor','w');
cbPW = uicheckbox(selGrid,'Text','PWM (0-255)', 'Value',0,'FontColor','w');
uilabel(selGrid,'Text','');
mkLabel(selGrid,'MOTORES',11,[0.6 0.6 0.6]);
motGrid = uigridlayout(selGrid,[1,3]); motGrid.Padding=[0 0 0 0];
cbM = cell(1,3);
cbM{1} = uicheckbox(motGrid,'Text','M1','Value',1,'FontColor',motorColors{1});
cbM{2} = uicheckbox(motGrid,'Text','M2','Value',1,'FontColor',motorColors{2});
cbM{3} = uicheckbox(motGrid,'Text','M3','Value',1,'FontColor',motorColors{3});
uilabel(selGrid,'Text','');

% ── CALLBACKS ──
btnConnect.ButtonPushedFcn = @(~,~) conectar();
btnGo.ButtonPushedFcn      = @(~,~) moverRobot([]);
btnPD.ButtonPushedFcn      = @(~,~) enviarControl();
btnZero.ButtonPushedFcn    = @(~,~) ceroRobot();
btnTest.ButtonPushedFcn    = @(~,~) testMotores();
cbQ.ValueChangedFcn        = @(~,~) refrescarGrafica();
cbE.ValueChangedFcn        = @(~,~) refrescarGrafica();
cbPW.ValueChangedFcn       = @(~,~) refrescarGrafica();
for k=1:3; cbM{k}.ValueChangedFcn = @(~,~) refrescarGrafica(); end
fig.CloseRequestFcn = @(src,~) cerrar(src);

% Estado del rotate 3D
rotSt = struct('on',false,'az',45,'el',25,'pt',[0 0]);

% Dibujo inicial
st = getappdata(fig,'st');
dibujarRobot(ax3D, deg2rad(st.target_q), p, motorColors, true);
log_('Sistema listo. Conecta el ESP32.');

% ============================================================
%  HELPERS DE ESTADO — leer/escribir via appdata
% ============================================================
  function st = getSt(); st = getappdata(fig,'st'); end
  function setSt(st);    setappdata(fig,'st',st);   end

% ============================================================
%  CONEXIÓN
% ============================================================
  function conectar()
    st = getSt();
    try
      if ~st.connected
        st.port = serialport(ddPort.Value, 115200);
        st.port.Timeout = 0.1;   % evita que readline bloquee 10s
        configureTerminator(st.port, "LF");
        flush(st.port);
        st.connected = true;
        st.t0 = tic;
        setSt(st);  % guardar ANTES de configureCallback
        configureCallback(st.port, "terminator", @(~,~) leerTelemetria());
        btnConnect.Text = 'DESCONECTAR';
        btnConnect.BackgroundColor = cRed;
        writeline(st.port, 'DISARM');
        enviarPD(); enviarDeadband();
        % Crear header del CSV al conectar (modo write, limpia el anterior)
        lf = fopen('robot_log.csv','w');
        if lf ~= -1; fprintf(lf,'tiempo,q1,q2,q3,e1,e2,e3,pwm1,pwm2,pwm3\n'); fclose(lf); end
        log_('ESP32 conectado.');
      else
        configureCallback(st.port, "off");
        delete(st.port);
        st.connected = false;
        st.port = [];
        setSt(st);
        btnConnect.Text = 'CONECTAR';
        btnConnect.BackgroundColor = [0.2 0.5 0.8];
        log_('ESP32 desconectado.');
      end
    catch ME
      log_(['[!] ' ME.message]);
    end
  end

% ============================================================
%  MOVER ROBOT
% ============================================================
  function moverRobot(xyz_mm)
    st = getSt();
    if isempty(xyz_mm)
      xyz_m = [efX.Value; efY.Value; efZ.Value] / 1000;
    else
      xyz_m = xyz_mm(:) / 1000;
      efX.Value = xyz_mm(1);
      efY.Value = xyz_mm(2);
      efZ.Value = xyz_mm(3);
    end
    [q_des, err] = ikRobot(xyz_m, p);
    if any(isnan(q_des)); log_(['[!] LÍMITE: ' err]); return; end
    st.target_q = rad2deg(q_des);
    setSt(st);
    dibujarRobot(ax3D, q_des, p, motorColors, false);
    if st.connected
      cmd = sprintf('T,%.2f,%.2f,%.2f', st.target_q(1), st.target_q(2), st.target_q(3));
      writeline(st.port, cmd);
      log_(['>> ' cmd]);
    end
  end

% ============================================================
%  TEST DE MOTORES
%  Envía secuencia: M1→90° M1→0° M2→90° M2→0° M3→90° M3→0°
%  Monitorea el encoder vía telemetría para reportar pass/fail
% ============================================================
  function testMotores()
    st = getSt();
    if ~st.connected
      log_('[!] Conecta el ESP32 primero.'); return;
    end

    log_('');
    log_('══════════════════════════════');
    log_('  TEST DE MOTORES — Iniciando');
    log_('══════════════════════════════');

    btnTest.Enable = 'off';
    btnTest.Text   = '⏳ Probando...';
    st.testMode = true; setSt(st);

    % Deshabilitar callback — leerUnFrame leerá directo.
    % flush() limpia los ~11000 bytes acumulados en el buffer.
    try; configureCallback(st.port, "off"); catch; end
    try; flush(st.port); catch; end

    TEST_DEG = 15.0;
    DEADBAND = 6.0;   % tolerancia real con overshoot
    TIMEOUT  = 20.0;  % motores lentos bajo carga
    resultados = zeros(1,3);

    % Ir a cero usando el mismo mecanismo de lectura activa
    log_('  Llevando a posición cero...');
    enviarCmd('T,0.00,0.00,0.00');
    esperarPosicionMulti([0 0 0], DEADBAND, 5.0);

    for motor = 1:3
      if ~isvalid(fig); break; end
      nombre = motorNames{motor};
      log_(sprintf('-- %s --', nombre));

      tq = [0.0, 0.0, 0.0];
      tq(motor) = TEST_DEG;
      enviarCmd(sprintf('T,%.2f,%.2f,%.2f', tq(1), tq(2), tq(3)));
      log_(sprintf('  → %.0f°', TEST_DEG));
      ok1 = esperarPosicion(motor, TEST_DEG, DEADBAND, TIMEOUT);

      enviarCmd('T,0.00,0.00,0.00');
      log_('  ← 0°');
      ok2 = esperarPosicion(motor, 0.0, DEADBAND, TIMEOUT);

      if ok1 && ok2
        log_(sprintf('  %s: ✓ OK', nombre));
        resultados(motor) = 1;
      else
        st = getappdata(fig,'st'); pos_actual = st.current_q(motor);
        if abs(pos_actual) < 3
          log_(sprintf('  %s: ✗ No se movió (pos=%.1f°)', nombre, pos_actual));
        elseif pos_actual < 0
          log_(sprintf('  %s: ✗ Dirección invertida (pos=%.1f°)', nombre, pos_actual));
        else
          log_(sprintf('  %s: ✗ Llegó parcial (%.1f° / %.0f°)', nombre, pos_actual, TEST_DEG));
        end
        resultados(motor) = -1;
        enviarCmd('T,0.00,0.00,0.00');
        esperarPosicionMulti([0 0 0], DEADBAND, 5.0);
      end
    end

    log_('──────────────────────────────');
    log_('  RESULTADO FINAL:');
    for m = 1:3
      if resultados(m) == 1
        log_(sprintf('  ✓  %s', motorNames{m}));
      else
        log_(sprintf('  ✗  %s', motorNames{m}));
      end
    end
    log_('══════════════════════════════');

    if ~isvalid(fig); return; end
    st = getSt(); st.testMode = false; setSt(st);
    try; configureCallback(st.port, "terminator", @(~,~) leerTelemetria()); catch; end
    btnTest.Enable = 'on';
    btnTest.Text   = '▶  VERIFICAR LOS 3 MOTORES';
  end

  % Lee UN frame D, del serial y actualiza appdata.
  % Siempre descarta frames acumulados para leer el más reciente.
  function ok = leerUnFrame()
    ok = false;
    if ~isvalid(fig); return; end
    st = getappdata(fig,'st');
    if ~st.connected || isempty(st.port) || ~isvalid(st.port); return; end

    % Descartar frames acumulados en el buffer (>100 bytes = más de 2 frames)
    % Evita leer datos obsoletos de cuando el motor estaba en otra posición.
    try
      nb = st.port.NumBytesAvailable;
      if nb > 100
        read(st.port, nb, 'uint8');
        pause(0.025);  % esperar 2-3 frames frescos del ESP32 (10ms/frame)
      end
    catch; end

    % Esperar bytes disponibles máx 150ms
    t_wait = tic;
    while toc(t_wait) < 0.15
      if st.port.NumBytesAvailable > 0; break; end
      pause(0.005);
    end
    if st.port.NumBytesAvailable == 0; return; end

    % Leer línea como bytes crudos y convertir a string
    % (evita el error "Input should be a string" de readline en ciertos contextos)
    try
      raw = '';
      t_line = tic;
      while toc(t_line) < 0.1
        if st.port.NumBytesAvailable == 0; pause(0.002); continue; end
        b = read(st.port, 1, 'uint8');
        if b == 10; break; end   % LF = fin de línea
        if b ~= 13; raw = [raw char(b)]; end  % ignorar CR
      end
      raw = strtrim(raw);
    catch
      return;
    end

    if ~startsWith(raw,'D,'); return; end
    vals = sscanf(extractAfter(raw,'D,'), '%f,');
    if numel(vals) ~= 9; return; end

    st = getappdata(fig,'st');
    st.current_q = vals(1:3)';
    st.pwm       = vals(7:9)';
    t_now        = toc(st.t0);
    st.time      = [st.time,     t_now     ];
    st.data_q    = [st.data_q,   vals(1:3) ];
    st.data_e    = [st.data_e,   vals(4:6) ];
    st.data_pwm  = [st.data_pwm, vals(7:9) ];
    MAX_S = 400; N = numel(st.time);
    if N > MAX_S
      keep = N-MAX_S+1:N;
      st.time=st.time(keep); st.data_q=st.data_q(:,keep);
      st.data_e=st.data_e(:,keep); st.data_pwm=st.data_pwm(:,keep);
    end
    setappdata(fig,'st',st);
    if isvalid(fig)
      dibujarRobot(ax3D, deg2rad(st.current_q), p, motorColors, false);
      refrescarGrafica();
      drawnow limitrate;
    end
    ok = true;
  end

  function ok = esperarPosicion(motorIdx, target_deg, db, timeout_s)
    t0  = tic;
    ok  = false;
    while toc(t0) < timeout_s
      if ~isvalid(fig); return; end
      leerUnFrame();
      pos = getappdata(fig,'st').current_q(motorIdx);
      if abs(pos - target_deg) < db
        if isvalid(fig)
          log_(sprintf('    llegó a %.1f° (err=%.1f°)', pos, pos-target_deg));
        end
        ok = true; return;
      end
    end
    if isvalid(fig)
      pos = getappdata(fig,'st').current_q(motorIdx);
      log_(sprintf('    TIMEOUT — pos=%.1f° err=%.1f°', pos, pos-target_deg));
    end
  end

  function esperarPosicionMulti(targets, db, timeout_s)
    t0 = tic;
    while toc(t0) < timeout_s
      if ~isvalid(fig); return; end
      leerUnFrame();
      st = getappdata(fig,'st');
      if all(abs(st.current_q - targets) < db); return; end
    end
  end

  % Helper: writeline seguro — siempre toma el puerto fresco de appdata
  function enviarCmd(cmd)
    if ~isvalid(fig); return; end
    st = getappdata(fig,'st');
    if ~st.connected || isempty(st.port) || ~isvalid(st.port); return; end
    try; writeline(st.port, cmd); catch; end
  end

% ============================================================
%  GANANCIAS / DEADBAND / ZERO
% ============================================================
  function enviarControl()
    enviarPD();
    enviarDeadband();
  end

  function enviarPD()
    st = getSt();
    if ~st.connected; return; end
    writeline(st.port, sprintf('K1,%.3f,%.4f', efP1.Value, efD1.Value));
    writeline(st.port, sprintf('K2,%.3f,%.4f', efP2.Value, efD2.Value));
    writeline(st.port, sprintf('K3,%.3f,%.4f', efP3.Value, efD3.Value));
    log_('>> Ganancias PD actualizadas.');
  end

  function enviarDeadband()
    st = getSt();
    if ~st.connected; return; end
    writeline(st.port, sprintf('DB,%.2f,%.2f,%.2f',...
      efDB1.Value, efDB2.Value, efDB3.Value));
    log_(sprintf('>> Zona muerta: %.1f° %.1f° %.1f°',...
      efDB1.Value, efDB2.Value, efDB3.Value));
  end

  function ceroRobot()
    st = getSt();
    if ~st.connected; return; end
    writeline(st.port,'ZERO');
    st.target_q = [0 0 0];
    setSt(st);
    dibujarRobot(ax3D, [0 0 0], p, motorColors, false);
    log_('>> ZERO enviado.');
  end

% ============================================================
%  INTERACCIÓN 3D
% ============================================================
  function iniciarInteraccion(src)
    mod = get(fig,'CurrentModifier');
    if any(strcmp(mod,'shift'))
      cp = src.CurrentPoint; pt = cp(1,:);
      zc = max(0.01, min(pt(3), p.L1+p.L2+p.L3));
      xyz_mm = [pt(1)*1000, pt(2)*1000, zc*1000];
      log_(sprintf('>> Click → X=%.0f Y=%.0f Z=%.0f mm', xyz_mm(1), xyz_mm(2), xyz_mm(3)));
      moverRobot(xyz_mm);
    else
      rotSt.on=true; rotSt.az=ax3D.View(1); rotSt.el=ax3D.View(2);
      rotSt.pt=get(fig,'CurrentPoint');
      fig.WindowButtonMotionFcn = @(~,~) rotarVista();
      fig.WindowButtonUpFcn     = @(~,~) soltarRotate();
    end
  end

  function rotarVista()
    if ~rotSt.on; return; end
    cp = get(fig,'CurrentPoint');
    view(ax3D, rotSt.az-(cp(1)-rotSt.pt(1))*0.5, ...
               max(-89,min(89, rotSt.el+(cp(2)-rotSt.pt(2))*0.5)));
  end

  function soltarRotate()
    rotSt.on=false;
    fig.WindowButtonMotionFcn=''; fig.WindowButtonUpFcn='';
  end

% ============================================================
%  TELEMETRÍA — callback de configureCallback
%  Usa read() en vez de readline() — readline() tiene comportamiento
%  inconsistente dentro de callbacks (puede leer la línea siguiente
%  o retornar vacío). read() sobre NumBytesAvailable siempre funciona.
% ============================================================
  function leerTelemetria()
    persistent last_draw_t;
    if isempty(last_draw_t); last_draw_t = 0; end

    % Leer todos los bytes disponibles
    try
      st = getappdata(fig,'st');
      if ~st.connected || isempty(st.port) || ~isvalid(st.port); return; end
      nb = st.port.NumBytesAvailable;
      if nb == 0; return; end
      raw_all = char(read(st.port, nb, 'uint8'));
    catch; return; end

    % Extraer la última línea D, completa (frame más reciente)
    lines = strsplit(raw_all, char(10));
    raw = '';
    for k = numel(lines):-1:1
      candidate = strtrim(lines{k});
      if startsWith(candidate, 'D,')
        raw = candidate; break;
      end
    end
    if isempty(raw); return; end

    vals = sscanf(extractAfter(raw, 'D,'), '%f,');
    if numel(vals) ~= 9; return; end

    st = getappdata(fig,'st');
    st.current_q = vals(1:3)';
    st.pwm       = vals(7:9)';
    t_now        = toc(st.t0);

    % Log CSV
    logFile = fopen('robot_log.csv', 'a');
    if logFile ~= -1
      fprintf(logFile, '%.3f,%.2f,%.2f,%.2f,%.3f,%.3f,%.3f,%d,%d,%d\n', ...
        t_now, vals(1), vals(2), vals(3), vals(4), vals(5), vals(6), ...
        int32(vals(7)), int32(vals(8)), int32(vals(9)));
      fclose(logFile);
    end

    st.time     = [st.time,     t_now     ];
    st.data_q   = [st.data_q,   vals(1:3) ];
    st.data_e   = [st.data_e,   vals(4:6) ];
    st.data_pwm = [st.data_pwm, vals(7:9) ];

    MAX_S = 400; N = numel(st.time);
    if N > MAX_S
      keep = (N-MAX_S+1):N;
      st.time     = st.time(keep);
      st.data_q   = st.data_q(:,  keep);
      st.data_e   = st.data_e(:,  keep);
      st.data_pwm = st.data_pwm(:,keep);
    end

    setappdata(fig,'st',st);

    % Refrescar UI a ~25 Hz (no a 100 Hz) para no saturar el render
    if (t_now - last_draw_t) > 0.04
      last_draw_t = t_now;
      if isvalid(fig)
        dibujarRobot(ax3D, deg2rad(st.current_q), p, motorColors, false);
        refrescarGrafica();
        drawnow;
      end
    end
  end

% ============================================================
%  GRÁFICA
% ============================================================
  function refrescarGrafica()
    st = getSt();
    N = numel(st.time);
    if N < 2; return; end

    if     cbQ.Value;  datos = st.data_q;   ylab='Posición (°)'; tit='Posición Articular';
    elseif cbE.Value;  datos = st.data_e;   ylab='Error (°)';    tit='Error Articular';
    elseif cbPW.Value; datos = st.data_pwm; ylab='PWM (0-255)';  tit='Señal PWM';
    else; return; end

    if size(datos,1)~=3 || size(datos,2)~=N; return; end

    cla(axCtrl); hold(axCtrl,'on'); grid(axCtrl,'on');

    estilos = {'-','-','--'};
    hay = false;
    for k=1:3
      if cbM{k}.Value
        plot(axCtrl, st.time, datos(k,:), estilos{k},...
          'Color',motorColors{k},'LineWidth',2,'DisplayName',motorNames{k});
        hay = true;
      end
    end

    axCtrl.Title.String=''; title(axCtrl, tit, 'Color','w');
    xlabel(axCtrl,'Tiempo (s)','Color','w');
    ylabel(axCtrl, ylab,'Color','w');
    axCtrl.XColor='w'; axCtrl.YColor='w';
    axCtrl.Color=[0.05 0.07 0.10];

    if hay
      tmin=st.time(1); tmax=st.time(end);
      if tmax<=tmin; tmax=tmin+0.5; end
      xlim(axCtrl,[tmin tmax]);
      legend(axCtrl,'TextColor','w','Location','northeast','Color',[0.1 0.1 0.1]);
    end
    drawnow limitrate;
  end

% ============================================================
%  CIERRE / LOG
% ============================================================
  function cerrar(src)
    try
      st = getSt();
      if st.connected && ~isempty(st.port) && isvalid(st.port)
        configureCallback(st.port,"off"); delete(st.port);
      end
    catch; end
    delete(src);
  end

  function log_(msg)
    if ~isvalid(fig); return; end
    txtLog.Value = [txtLog.Value; {msg}];
    txtLog.scroll('bottom');
  end

end % robotGUI

% ============================================================
%  CINEMÁTICA INVERSA
% ============================================================
function [q, errMsg] = ikRobot(pos, p)
  q=[NaN NaN NaN]; errMsg='';
  x=pos(1); y=pos(2); z=pos(3);
  if z<0; errMsg='Z < 0.'; return; end
  q1=atan2(y,x); r=sqrt(x^2+y^2); z_rel=z-p.L1;
  D3d=sqrt(r^2+z_rel^2);
  if D3d>(p.L2+p.L3); errMsg='Fuera de alcance.'; return; end
  if D3d<0.05;         errMsg='Singularidad.'; return; end
  D=max(-1,min(1,(r^2+z_rel^2-p.L2^2-p.L3^2)/(2*p.L2*p.L3)));
  q3=atan2(-sqrt(1-D^2),D);
  q2=atan2(z_rel,r)-atan2(p.L3*sin(q3),p.L2+p.L3*cos(q3));
  q=[q1,q2,q3];
end

% ============================================================
%  DIBUJO 3D
% ============================================================
function dibujarRobot(ax, q, p, motorColors, resetView)
  if ~resetView; cv=ax.View; end
  cla(ax); hold(ax,'on');
  O=[0;0;0]; P1=[0;0;p.L1];
  P2=P1+[cos(q(1))*cos(q(2))*p.L2; sin(q(1))*cos(q(2))*p.L2; sin(q(2))*p.L2];
  P3=P2+[cos(q(1))*cos(q(2)+q(3))*p.L3; sin(q(1))*cos(q(2)+q(3))*p.L3; sin(q(2)+q(3))*p.L3];
  pts=[O,P1,P2,P3];
  for k=1:3
    plot3(ax,pts(1,k:k+1),pts(2,k:k+1),pts(3,k:k+1),'-','LineWidth',5,'Color',motorColors{k});
  end
  scatter3(ax,pts(1,:),pts(2,:),pts(3,:),80,'w','filled');
  scatter3(ax,P3(1),P3(2),P3(3),120,[1 0.3 0.3],'filled','p');
  plot3(ax,[0 P3(1)],[0 P3(2)],[0 0],'--','Color',[0.3 0.3 0.3],'LineWidth',1);
  ax.XLim=[-0.45 0.45]; ax.YLim=[-0.45 0.45]; ax.ZLim=[0 0.55];
  ax.XLabel.String='X'; ax.YLabel.String='Y'; ax.ZLabel.String='Z';
  ax.XLabel.Color='w'; ax.YLabel.Color='w'; ax.ZLabel.Color='w';
  grid(ax,'on');
  if resetView; view(ax,45,25); else; view(ax,cv(1),cv(2)); end
end

% ============================================================
%  PARÁMETROS / HELPERS
% ============================================================
function p = robotParams()
  p.L1=0.100; p.L2=0.205; p.L3=0.16569;
end

function estilo3D(ax,tit)
  ax.Color=[0.05 0.07 0.10]; ax.XColor='w'; ax.YColor='w'; ax.ZColor='w';
  ax.GridColor=[0.2 0.2 0.3]; title(ax,tit,'Color','w','FontSize',10);
end

function estiloAx(ax,tit)
  ax.Color=[0.05 0.07 0.10]; ax.XColor='w'; ax.YColor='w';
  ax.GridColor=[0.2 0.2 0.3];
  title(ax,tit,'Color','w','FontSize',11); hold(ax,'on'); grid(ax,'on');
end

function lbl = mkLabel(parent,txt,sz,col)
  lbl=uilabel(parent,'Text',txt,'FontSize',sz,'FontWeight','bold','FontColor',col);
end

function ef = mkEdit(parent,val)
  ef=uieditfield(parent,'numeric','Value',val,...
    'BackgroundColor',[0.08 0.10 0.14],'FontColor','w');
end

function [efP,efD] = motorRow(parent,name,col,vP,vD)
  g=uigridlayout(parent,[1,5]); g.Padding=[0 0 0 0]; g.ColumnSpacing=4;
  lbl=uilabel(g,'Text',name,'FontColor',col,'FontWeight','bold');
  lbl.HorizontalAlignment='right';
  uilabel(g,'Text','Kp','FontColor','w','HorizontalAlignment','right');
  efP=mkEdit(g,vP);
  uilabel(g,'Text','Kd','FontColor','w','HorizontalAlignment','right');
  efD=mkEdit(g,vD);
end

