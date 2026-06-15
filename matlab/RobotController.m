%
% ============================================================
%  RobotController.m – Robot RRR 3DOF | GUI (Paralelogramo)
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

% ── Estado como AppData de la figura ──
initState = struct(...
  'port',      [], ...
  'connected', false, ...
  'target_q',  [0 90 -90], ...
  'current_q', [0 0 0], ...
  'home_q',    [0 90 -90], ...
  'pwm',       [0 0 0], ...
  'time',      [], ...
  'data_q',    zeros(3,0), ...
  'data_e',    zeros(3,0), ...
  'data_pwm',  zeros(3,0), ...
  't0',        0, ...
  'testMode',  false, ...
  'stopTest',  false, ...
  'pos1',      [], ...  % Coordenada 1 guardada
  'pos2',      []  ...  % Coordenada 2 guardada
);

% ── FIGURA ──
% Layout 3 columnas: C1=280px (parámetros) | C2=280px (control) | C3=1x (3D+gráficas)
fig = uifigure('Name','Robot RRR 3DOF — Control PD (Paralelogramo)', 'Color', cBg);
fig.Position(3:4) = [1600 980];
setappdata(fig,'st', initState);

mainGrid = uigridlayout(fig, [2,3]);
mainGrid.ColumnWidth   = {280, 280, '1x'};
mainGrid.RowHeight     = {'1x', 260};
mainGrid.Padding       = [6 6 6 6];
mainGrid.RowSpacing    = 6;
mainGrid.ColumnSpacing = 6;

% ── COLUMNA 1: DESTINO · SECUENCIA · GANANCIAS PD · ZONA MUERTA ──
pnlC1 = uipanel(mainGrid,'BackgroundColor',cPanel,'BorderType','none');
pnlC1.Layout.Row=[1 2]; pnlC1.Layout.Column=1;

g1 = uigridlayout(pnlC1,[16,1]);
g1.Padding    = [8 8 8 8];
g1.RowHeight  = {22,36,40,10, 22,36,36,10, 22,36,36,36,40,10, 22,36};
g1.RowSpacing = 5;

% DESTINO (X Y Z)
mkLabel(g1,'▸ DESTINO (mm)', 13, cAccent);
gXYZ = uigridlayout(g1,[1,6]); gXYZ.Padding=[0 0 0 0]; gXYZ.ColumnSpacing=4;
uilabel(gXYZ,'Text','X','FontColor','w','HorizontalAlignment','right','FontSize',12);
efX = mkEdit(gXYZ, 165.69);
uilabel(gXYZ,'Text','Y','FontColor','w','HorizontalAlignment','right','FontSize',12);
efY = mkEdit(gXYZ, 0);
uilabel(gXYZ,'Text','Z','FontColor','w','HorizontalAlignment','right','FontSize',12);
efZ = mkEdit(gXYZ, 305);
btnGo = uibutton(g1,'push','Text','⟶  EJECUTAR TRAYECTORIA',...
  'BackgroundColor',cAccent,'FontWeight','bold','FontColor',[0 0 0],'FontSize',12);
uilabel(g1,'Text','');

% SECUENCIA P1 ↔ P2
mkLabel(g1,'▸ SECUENCIA  P1 ↔ P2', 13, [0.9 0.8 0.2]);
gSeq1 = uigridlayout(g1,[1,2]); gSeq1.Padding=[0 0 0 0]; gSeq1.ColumnSpacing=6;
btnSave1 = uibutton(gSeq1,'push','Text','[1]  Guardar Pos 1',...
  'BackgroundColor',[0.2 0.4 0.6],'FontColor','w','FontSize',11);
btnSave2 = uibutton(gSeq1,'push','Text','[2]  Guardar Pos 2',...
  'BackgroundColor',[0.2 0.6 0.4],'FontColor','w','FontSize',11);
gSeq2 = uigridlayout(g1,[1,2]); gSeq2.Padding=[0 0 0 0]; gSeq2.ColumnSpacing=6;
btnRunSeq  = uibutton(gSeq2,'push','Text','▶  EJECUTAR (8×)',...
  'BackgroundColor',[0.9 0.8 0.2],'FontWeight','bold','FontColor',[0 0 0],'FontSize',11);
btnStopSeq = uibutton(gSeq2,'push','Text','■  DETENER',...
  'BackgroundColor',cRed,'FontWeight','bold','FontColor','w','FontSize',11,'Enable','off');
uilabel(g1,'Text','');

% GANANCIAS PD  (valores por defecto = firmware actual: Kp=6, Kd=0.08)
mkLabel(g1,'▸ GANANCIAS PD', 13, cWarn);
[efP1,efD1] = motorRow(g1,'M1 Base  ', motorColors{1}, 6.0, 0.08);
[efP2,efD2] = motorRow(g1,'M2 Hombro', motorColors{2}, 6.0, 0.08);
[efP3,efD3] = motorRow(g1,'M3 Codo  ', motorColors{3}, 6.0, 0.08);
btnPD = uibutton(g1,'push','Text','↻  ACTUALIZAR GANANCIAS',...
  'BackgroundColor',cWarn,'FontWeight','bold','FontColor',[0 0 0],'FontSize',12);
uilabel(g1,'Text','');

% ZONA MUERTA
mkLabel(g1,'▸ ZONA MUERTA (°)', 13, [0.7 0.5 0.9]);
gDB = uigridlayout(g1,[1,6]); gDB.Padding=[0 0 0 0]; gDB.ColumnSpacing=4;
uilabel(gDB,'Text','M1','FontColor','w','FontSize',11); efDB1 = mkEdit(gDB, 2.0);
uilabel(gDB,'Text','M2','FontColor','w','FontSize',11); efDB2 = mkEdit(gDB, 2.0);
uilabel(gDB,'Text','M3','FontColor','w','FontSize',11); efDB3 = mkEdit(gDB, 2.0);

% ── COLUMNA 2: CONTROL MANUAL · TEST · CONEXIÓN · CERO · FK · LOG ──
pnlC2 = uipanel(mainGrid,'BackgroundColor',cPanel,'BorderType','none');
pnlC2.Layout.Row=[1 2]; pnlC2.Layout.Column=2;

g2 = uigridlayout(pnlC2,[20,1]);
g2.Padding    = [8 8 8 8];
g2.RowHeight  = {22,22,22,10, 22,44,36,36,10, 36,10, 44,22,40,10, 22,36,40,22,120};
g2.RowSpacing = 5;

% CONTROL MANUAL (teclado)
mkLabel(g2,'▸ CONTROL MANUAL (teclado)', 13, [0.85 0.85 0.50]);
uilabel(g2,'Text','A/D → M1 ±5°     W/S → M2 ±5°     Q/E → M3 ±5°',...
  'FontColor',[0.75 0.75 0.75],'FontSize',11,'BackgroundColor',cPanel);
uilabel(g2,'Text','[ESPACIO] = DISARM (emergencia)     [R] = ZERO',...
  'FontColor',cRed,'FontSize',11,'FontWeight','bold','BackgroundColor',cPanel);
uilabel(g2,'Text','');

% TEST MOTORES
mkLabel(g2,'▸ TEST MOTORES', 13, cPurple);
btnTest = uibutton(g2,'push','Text','▶  VERIFICAR LOS 3 MOTORES',...
  'BackgroundColor',cPurple,'FontWeight','bold','FontColor','w','FontSize',12);
btnStop = uibutton(g2,'push','Text','■  PARAR PRUEBA',...
  'BackgroundColor',[0.6 0.1 0.1],'FontWeight','bold','FontColor','w','FontSize',12,'Enable','off');
gMotInd = uigridlayout(g2,[1,3]);
gMotInd.Padding=[0 0 0 0]; gMotInd.ColumnSpacing=6;
btnM1 = uibutton(gMotInd,'push','Text','▶ M1','BackgroundColor',motorColors{1},'FontColor',[0 0 0],'FontWeight','bold','FontSize',12);
btnM2 = uibutton(gMotInd,'push','Text','▶ M2','BackgroundColor',motorColors{2},'FontColor',[0 0 0],'FontWeight','bold','FontSize',12);
btnM3 = uibutton(gMotInd,'push','Text','▶ M3','BackgroundColor',motorColors{3},'FontColor',[0 0 0],'FontWeight','bold','FontSize',12);
uilabel(g2,'Text','');

% CONEXIÓN
gSerial = uigridlayout(g2,[1,3]);
gSerial.Padding=[0 0 0 0]; gSerial.ColumnSpacing=6; gSerial.ColumnWidth={'1x',38,92};
ddPort     = uidropdown(gSerial,'Items',serialportlist("available"),...
  'BackgroundColor',cPanel2,'FontColor','w','FontSize',11);
btnRefresh = uibutton(gSerial,'push','Text','⟳','BackgroundColor',[0.18 0.22 0.30],...
  'FontColor','w','FontSize',15,'Tooltip','Actualizar lista de puertos');
btnConnect = uibutton(gSerial,'push','Text','CONECTAR','BackgroundColor',[0.2 0.5 0.8],...
  'FontColor','w','FontSize',11,'FontWeight','bold');
uilabel(g2,'Text','');

% CALIBRACIÓN / CERO
btnFree = uibutton(g2,'push','Text','⚡  SOLTAR CORRIENTE  (mover robot a mano)',...
  'BackgroundColor',[0.70 0.35 0.00],'FontWeight','bold','FontColor','w','FontSize',12);
mkLabel(g2,'▸ POSICIÓN CERO — coloca el robot en L invertida:', 12, cOk);
btnZero = uibutton(g2,'push','Text','⊙  REGISTRAR CERO  (activa y mantiene posición)',...
  'BackgroundColor',[0.05 0.40 0.15],'FontWeight','bold','FontColor','w','FontSize',12);
uilabel(g2,'Text','');

% CINEMÁTICA DIRECTA
mkLabel(g2,'▸ CINEMÁTICA DIRECTA (°)', 13, [0.85 0.65 0.20]);
gFK = uigridlayout(g2,[1,6]); gFK.Padding=[0 0 0 0]; gFK.ColumnSpacing=4;
uilabel(gFK,'Text','θ1','FontColor',[0.85 0.65 0.20],'HorizontalAlignment','right','FontSize',12);
efFK1 = mkEdit(gFK, 0);
uilabel(gFK,'Text','θ2','FontColor',[0.85 0.65 0.20],'HorizontalAlignment','right','FontSize',12);
efFK2 = mkEdit(gFK, 0);
uilabel(gFK,'Text','θ3','FontColor',[0.85 0.65 0.20],'HorizontalAlignment','right','FontSize',12);
efFK3 = mkEdit(gFK, 0);
btnFK = uibutton(g2,'push','Text','↗  ENVIAR ÁNGULOS',...
  'BackgroundColor',[0.55 0.40 0.10],'FontWeight','bold','FontColor','w','FontSize',12);
mkLabel(g2,'▸ LOG', 12, [0.5 0.5 0.5]);
txtLog = uitextarea(g2,'BackgroundColor',[0 0 0],'FontColor',[0 0.9 0.3],...
  'Editable',false,'FontSize',10);

% ── COLUMNA 3: MODELO 3D (fila 1) + GRÁFICAS DE CONTROL (fila 2) ──
ax3D = uiaxes(mainGrid,'Color',cBg);
ax3D.Layout.Row=1; ax3D.Layout.Column=3;
estilo3D(ax3D,'Modelo 3D  |  Arrastrar=Rotar   Shift+Click=Mover');
disableDefaultInteractivity(ax3D);
ax3D.ButtonDownFcn = @(src,~) iniciarInteraccion(src);

lblAngulos = uilabel(mainGrid,...
  'Text','θ1: ---°   θ2: ---°   θ3: ---°',...
  'FontColor',[0.6 0.9 1.0],'FontSize',13,'FontWeight','bold',...
  'BackgroundColor','none','HorizontalAlignment','left');
lblAngulos.Layout.Row=1; lblAngulos.Layout.Column=3;

pnlGraf = uipanel(mainGrid,'BackgroundColor',cPanel,'BorderType','none');
pnlGraf.Layout.Row=2; pnlGraf.Layout.Column=3;
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
btnRefresh.ButtonPushedFcn = @(~,~) refrescarPuertos();
btnGo.ButtonPushedFcn      = @(~,~) moverRobot([]);
btnSave1.ButtonPushedFcn   = @(~,~) savePos1();
btnSave2.ButtonPushedFcn   = @(~,~) savePos2();
btnRunSeq.ButtonPushedFcn  = @(~,~) runSequence();
btnStopSeq.ButtonPushedFcn = @(~,~) pararPrueba(); 
btnPD.ButtonPushedFcn      = @(~,~) enviarControl();
btnFree.ButtonPushedFcn    = @(~,~) soltarCorrente();
btnZero.ButtonPushedFcn    = @(~,~) ceroRobot();
btnFK.ButtonPushedFcn      = @(~,~) enviarCinematicaDirecta();
btnTest.ButtonPushedFcn    = @(~,~) testMotores();
btnStop.ButtonPushedFcn    = @(~,~) pararPrueba();
btnM1.ButtonPushedFcn      = @(~,~) testMotorUnico(1);
btnM2.ButtonPushedFcn      = @(~,~) testMotorUnico(2);
btnM3.ButtonPushedFcn      = @(~,~) testMotorUnico(3);

cbQ.ValueChangedFcn        = @(~,~) refrescarGrafica();
cbE.ValueChangedFcn        = @(~,~) refrescarGrafica();
cbPW.ValueChangedFcn       = @(~,~) refrescarGrafica();
for k=1:3; cbM{k}.ValueChangedFcn = @(~,~) refrescarGrafica(); end
fig.CloseRequestFcn = @(src,~) cerrar(src);
fig.KeyPressFcn     = @(~,ev)  teclasRobot(ev);

% Estado del rotate 3D
rotSt = struct('on',false,'az',45,'el',25,'pt',[0 0]);
% Dibujo inicial
st = getappdata(fig,'st');
dibujarRobot(ax3D, deg2rad(st.target_q), p, motorColors, true);
log_('Sistema listo. Conecta el ESP32.');

% ============================================================
%  HELPERS DE ESTADO
% ============================================================
  function st = getSt(); st = getappdata(fig,'st'); end
  function setSt(st);    setappdata(fig,'st',st);   end

% ============================================================
%  CONEXIÓN
% ============================================================
  function refrescarPuertos()
    puertos = serialportlist("available");
    if isempty(puertos)
      ddPort.Items = {''};
      log_('[!] No se detectaron puertos seriales. Verifica que el ESP32 esté conectado.');
    else
      ddPort.Items = puertos;
      ddPort.Value = puertos{1};
      log_(sprintf('>> Puertos detectados: %s', strjoin(puertos, ', ')));
    end
  end

  function conectar()
    st = getSt();
    try
      if ~st.connected
        st.port = serialport(ddPort.Value, 115200);
        st.port.Timeout = 0.1;
        configureTerminator(st.port, "LF");
        flush(st.port);
        st.connected = true;
        st.t0 = tic;
        setSt(st);  
        configureCallback(st.port, "terminator", @(~,~) leerTelemetria());
        btnConnect.Text = 'DESCONECTAR';
        btnConnect.BackgroundColor = cRed;
        btnZero.BackgroundColor = [0.05 0.40 0.15];
        btnZero.Text = '[ ] REGISTRAR CERO  (coloca el robot en L invertida primero)';
        writeline(st.port, 'DISARM');
        enviarPD(); enviarDeadband();
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
%  SECUENCIA AUTOMÁTICA
% ============================================================
  function savePos1()
    st = getSt();
    st.pos1 = [efX.Value, efY.Value, efZ.Value];
    setSt(st);
    btnSave1.Text = sprintf('P1: [%.0f, %.0f, %.0f]', st.pos1(1), st.pos1(2), st.pos1(3));
    log_(sprintf('>> Posición 1 guardada: X=%.0f, Y=%.0f, Z=%.0f', st.pos1(1), st.pos1(2), st.pos1(3)));
  end

  function savePos2()
    st = getSt();
    st.pos2 = [efX.Value, efY.Value, efZ.Value];
    setSt(st);
    btnSave2.Text = sprintf('P2: [%.0f, %.0f, %.0f]', st.pos2(1), st.pos2(2), st.pos2(3));
    log_(sprintf('>> Posición 2 guardada: X=%.0f, Y=%.0f, Z=%.0f', st.pos2(1), st.pos2(2), st.pos2(3)));
  end

  function runSequence()
    st = getSt();
    if isempty(st.pos1) || isempty(st.pos2)
      log_('[!] ERROR: Primero debes guardar Posición 1 y Posición 2.');
      return;
    end
    if ~st.connected
      log_('[!] Conecta el ESP32 primero.');
      return;
    end
    log_('');
    log_('══════════════════════════════');
    log_('  INICIANDO SECUENCIA (8 Repeticiones)');
    log_('══════════════════════════════');
    
    % Bloquear UI
    btnRunSeq.Enable = 'off';
    btnStopSeq.Enable = 'on';
    btnGo.Enable = 'off';
    btnTest.Enable = 'off';
    
    st.testMode = true; st.stopTest = false; setSt(st);
    
    try; configureCallback(st.port, "off"); catch; end
    try; flush(st.port); catch; end
    
    % --- CONFIGURACIÓN DE TOLERANCIAS ---
    % Un poco más alto para tolerar oscilaciones mecánicas de los JGA25
    DEADBAND = 8.0;   
    % Timeout más corto: si no llega exacto en 6 segs, igual avanza a la siguiente pos.
    TIMEOUT  = 6.0;  
    
    % CORRECCIÓN DE COORDENADAS: 
    % ikRobot da ángulos físicos absolutos (ej. 90°), pero el encoder mide relativo al home (ej. 0°)
    [q_des1, ~] = ikRobot(st.pos1 / 1000, p);
    fw_target1 = rad2deg(q_des1) - st.home_q;
    fw_target1(2) = -fw_target1(2);
    fw_target1(3) = -fw_target1(3);

    [q_des2, ~] = ikRobot(st.pos2 / 1000, p);
    fw_target2 = rad2deg(q_des2) - st.home_q;
    fw_target2(2) = -fw_target2(2);
    fw_target2(3) = -fw_target2(3);

    for rep = 1:8
      if ~isvalid(fig); break; end
      if getappdata(fig,'st').stopTest; break; end
      
      % --- IR A POS 1 ---
      log_(sprintf('► Ciclo %d/8 - Moviendo a Posición 1', rep));
      moverRobot(st.pos1); 
      llegada = esperarPosicionMulti(fw_target1, DEADBAND, TIMEOUT);
      
      if ~llegada
         log_('    (Avanzando por timeout - posible sobreimpulso/oscilación)');
      end
      pause(0.2); % Breve pausa para no estresar los motores al cambiar de dirección
      
      if ~isvalid(fig); break; end
      if getappdata(fig,'st').stopTest; break; end
      
      % --- IR A POS 2 ---
      log_(sprintf('► Ciclo %d/8 - Moviendo a Posición 2', rep));
      moverRobot(st.pos2);
      llegada = esperarPosicionMulti(fw_target2, DEADBAND, TIMEOUT);
      
      if ~llegada
         log_('    (Avanzando por timeout - posible sobreimpulso/oscilación)');
      end
      pause(0.2);
    end

    if getappdata(fig,'st').stopTest
        log_('>> Secuencia INTERRUMPIDA.');
    else
        log_('>> Secuencia FINALIZADA con éxito.');
    end
    log_('══════════════════════════════');
    
    if ~isvalid(fig); return; end
    st = getSt(); st.testMode = false; st.stopTest = false; setSt(st);
    try; configureCallback(st.port, "terminator", @(~,~) leerTelemetria()); catch; end
    
    % Restaurar UI
    btnRunSeq.Enable = 'on';
    btnStopSeq.Enable = 'off';
    btnGo.Enable = 'on';
    btnTest.Enable = 'on';
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
    [q_des, ikErr] = ikRobot(xyz_m, p);
    if ~isempty(ikErr)
      log_(['[!] IK: ' ikErr ' — enviando posición aproximada']);
    end
    st.target_q = rad2deg(q_des);
    setSt(st);

    q_fw = st.target_q - st.home_q;
    q_fw(2) = -q_fw(2);
    q_fw(3) = -q_fw(3);
    efFK1.Value = round(q_fw(1), 2);
    efFK2.Value = round(q_fw(2), 2);
    efFK3.Value = round(q_fw(3), 2);

    dibujarRobot(ax3D, q_des, p, motorColors, false);

    if st.connected
      cmd = sprintf('T,%.2f,%.2f,%.2f', q_fw(1), q_fw(2), q_fw(3));
      writeline(st.port, cmd);
      log_(['>> ' cmd ' (fisica: ' sprintf('%.1f,%.1f,%.1f deg', st.target_q) ')']);
    end
  end

% ============================================================
%  TEST DE MOTORES
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
    btnStop.Enable = 'on';
    st.testMode = true; st.stopTest = false; setSt(st);
    
    try; configureCallback(st.port, "off"); catch; end
    try; flush(st.port); catch; end
    
    TEST_DEG = 50.0;
    DEADBAND = 6.0;
    TIMEOUT  = 20.0;
    resultados = zeros(1,3);
    
    log_('  Llevando a posición cero...');
    enviarCmd('T,0.00,0.00,0.00');
    esperarPosicionMulti([0 0 0], DEADBAND, 5.0);
    
    for motor = 1:3
      if ~isvalid(fig); break; end
      if getappdata(fig,'st').stopTest; break; end
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
    st = getSt(); st.testMode = false; st.stopTest = false; setSt(st);
    try; configureCallback(st.port, "terminator", @(~,~) leerTelemetria()); catch; end
    btnTest.Enable = 'on';
    btnTest.Text   = '▶  VERIFICAR LOS 3 MOTORES';
    btnStop.Enable = 'off';
  end

% ============================================================
%  TEST MOTOR INDIVIDUAL
% ============================================================
  function testMotorUnico(motorIdx)
    st = getSt();
    if ~st.connected; log_('[!] Conecta el ESP32 primero.'); return; end
    TEST_DEG = 90.0;
    DEADBAND = 6.0;
    TIMEOUT  = 20.0;
    nombre = motorNames{motorIdx};
    
    btnM1.Enable='off'; btnM2.Enable='off'; btnM3.Enable='off';
    btnStop.Enable = 'on';
    st = getSt(); st.testMode=true; st.stopTest=false; setSt(st);
    
    try; configureCallback(st.port,'off'); catch; end
    try; flush(st.port); catch; end
    
    log_('');
    log_(sprintf('── Test individual: %s ──', nombre));
    enviarCmd('T,0.00,0.00,0.00');
    esperarPosicionMulti([0 0 0], DEADBAND, 5.0);
    
    if ~getappdata(fig,'st').stopTest
      tq = [0.0, 0.0, 0.0]; tq(motorIdx) = TEST_DEG;
      enviarCmd(sprintf('T,%.2f,%.2f,%.2f', tq(1), tq(2), tq(3)));
      log_(sprintf('  → %.0f°', TEST_DEG));
      ok1 = esperarPosicion(motorIdx, TEST_DEG, DEADBAND, TIMEOUT);
      
      enviarCmd('T,0.00,0.00,0.00');
      log_('  ← 0°');
      ok2 = esperarPosicion(motorIdx, 0.0, DEADBAND, TIMEOUT);
      
      if ok1 && ok2; log_(sprintf('  %s: ✓ OK', nombre));
      else;          log_(sprintf('  %s: ✗ Revisar', nombre)); end
    end
    
    if ~isvalid(fig); return; end
    st = getSt(); st.testMode=false; st.stopTest=false; setSt(st);
    try; configureCallback(st.port,"terminator",@(~,~) leerTelemetria()); catch; end
    btnM1.Enable='on'; btnM2.Enable='on'; btnM3.Enable='on';
    btnStop.Enable = 'off';
  end

  function ok = leerUnFrame()
    ok = false;
    if ~isvalid(fig); return; end
    st = getappdata(fig,'st');
    if ~st.connected || isempty(st.port) || ~isvalid(st.port); return; end
    try
      nb = st.port.NumBytesAvailable;
      if nb > 100
        read(st.port, nb, 'uint8');
        pause(0.025);
      end
    catch; end
    t_wait = tic;
    while toc(t_wait) < 0.15
      if st.port.NumBytesAvailable > 0; break; end
      pause(0.005);
    end
    if st.port.NumBytesAvailable == 0; return; end
    try
      raw = '';
      t_line = tic;
      while toc(t_line) < 0.1
        if st.port.NumBytesAvailable == 0; pause(0.002); continue; end
        b = read(st.port, 1, 'uint8');
        if b == 10; break; end
        if b ~= 13; raw = [raw char(b)]; end
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
      q_vis = st.current_q;
      q_vis(2) = -st.current_q(2);
      q_vis(3) = -st.current_q(3);
      q_phys = q_vis + st.home_q;
      dibujarRobot(ax3D, deg2rad(q_phys), p, motorColors, false);
      lblAngulos.Text = sprintf('θ1: %.1f°   θ2: %.1f°   θ3: %.1f°', q_phys(1), q_phys(2), q_phys(3));

      t1=deg2rad(q_phys(1)); t2=deg2rad(q_phys(2)); t3=deg2rad(q_phys(3));
      r_=p.L2*cos(t2)+p.L3*cos(t3+pi/2);
      efX.Value=round(r_*cos(t1)*1000,2);
      efY.Value=round(r_*sin(t1)*1000,2);
      efZ.Value=round((p.L1+p.L2*sin(t2)+p.L3*sin(t3+pi/2))*1000,2);

      efFK1.Value=round(st.current_q(1),2);
      efFK2.Value=round(st.current_q(2),2);
      efFK3.Value=round(st.current_q(3),2);
      
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
      if getappdata(fig,'st').stopTest; return; end
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

  % Modificado para que retorne booleano y no estanque la secuencia
  function ok = esperarPosicionMulti(targets, db, timeout_s)
    t0 = tic;
    ok = false;
    while toc(t0) < timeout_s
      if ~isvalid(fig); return; end
      if getappdata(fig,'st').stopTest; return; end
      leerUnFrame();
      st = getappdata(fig,'st');
      if all(abs(st.current_q - targets) < db)
         ok = true;
         return; 
      end
    end
  end

  function enviarCmd(cmd)
    if ~isvalid(fig); return; end
    st = getappdata(fig,'st');
    if ~st.connected || isempty(st.port) || ~isvalid(st.port); return; end
    try; writeline(st.port, cmd); catch; end
  end

% ============================================================
%  CONTROL POR TECLADO
%  A/D=M1  W/S=M2  Q/E=M3  (±5° por tecla)
%  Espacio=DISARM  R=ZERO
% ============================================================
  function teclasRobot(event)
    if ~isvalid(fig); return; end
    st = getSt();
    if ~st.connected; return; end

    PASO = 5.0;
    LIMS = [-80 80; -45 45; -45 45];  % [neg pos] por motor en coords firmware
    tecla = event.Key;

    % Comandos de emergencia/reset
    if strcmp(tecla,'space')
      enviarCmd('DISARM');
      log_('[TECLADO] ESPACIO → DISARM');
      return;
    end
    if strcmpi(tecla,'r')
      log_('[TECLADO] R → ZERO');
      ceroRobot();
      return;
    end

    % Delta por tecla → coordenadas firmware
    delta = [0 0 0];
    switch lower(tecla)
      case 'a'; delta(1) = +PASO;
      case 'd'; delta(1) = -PASO;
      case 'w'; delta(2) = +PASO;
      case 's'; delta(2) = -PASO;
      case 'q'; delta(3) = +PASO;
      case 'e'; delta(3) = -PASO;
      otherwise; return;
    end

    % Setpoint actual convertido a coordenadas firmware
    fw_actual = st.target_q - st.home_q;
    fw_nuevo  = fw_actual + delta;

    % Aplicar límites
    nombres_m = {'M1','M2','M3'};
    for mi = 1:3
      if fw_nuevo(mi) < LIMS(mi,1)
        fw_nuevo(mi) = LIMS(mi,1);
        log_(sprintf('[TECLADO] %s: límite mínimo %.0f°', nombres_m{mi}, LIMS(mi,1)));
      elseif fw_nuevo(mi) > LIMS(mi,2)
        fw_nuevo(mi) = LIMS(mi,2);
        log_(sprintf('[TECLADO] %s: límite máximo %.0f°', nombres_m{mi}, LIMS(mi,2)));
      end
    end

    if any(fw_nuevo ~= fw_actual)
      cmd = sprintf('T,%.2f,%.2f,%.2f', fw_nuevo(1), fw_nuevo(2), fw_nuevo(3));
      enviarCmd(cmd);
      st.target_q = fw_nuevo + st.home_q;
      setSt(st);
      log_(sprintf('[TECLADO] %s → fw=[%.1f° %.1f° %.1f°]', ...
        upper(tecla), fw_nuevo(1), fw_nuevo(2), fw_nuevo(3)));
    end
  end

% ============================================================
%  PARAR PRUEBA / SECUENCIA
% ============================================================
  function pararPrueba()
    if ~isvalid(fig); return; end
    st = getSt(); st.stopTest = true; setSt(st);
    enviarCmd('DISARM');
    log_('══════════════════════════════');
    log_('  MOVIMIENTO DETENIDO POR USUARIO');
    log_('══════════════════════════════');
    try btnStop.Enable = 'off'; catch; end
    try btnTest.Enable = 'on'; catch; end
    try btnStopSeq.Enable = 'off'; catch; end
    try btnRunSeq.Enable = 'on'; catch; end
    try btnGo.Enable = 'on'; catch; end
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
  function soltarCorrente()
    st = getSt();
    if ~st.connected; log_('[!] Conecta el ESP32 primero.'); return; end
    writeline(st.port,'FREE');
    btnFree.BackgroundColor = [0.90 0.50 0.00];
    btnZero.BackgroundColor = [0.05 0.40 0.15];
    btnZero.Text = '[ ] REGISTRAR CERO  (activa y mantiene L invertida)';
    log_('══════════════════════════════');
    log_('⚡ CORRIENTE CORTADA — motores libres.');
    log_('   Mueve el brazo a la posición L invertida,');
    log_('   luego presiona REGISTRAR CERO.');
    log_('══════════════════════════════');
  end
  function ceroRobot()
    st = getSt();
    if ~st.connected
      log_('[!] Conecta el ESP32 primero.');
      return;
    end
    writeline(st.port,'ZERO');
    pause(0.15);
    writeline(st.port,'T,0,0,0');
    
    HOME_PHYS = [0, 90, -90];
    st.home_q    = HOME_PHYS;
    st.target_q  = HOME_PHYS;
    efX.Value = 165.69;
    efY.Value = 0;
    efZ.Value = 305;
    setSt(st);
    
    dibujarRobot(ax3D, deg2rad(HOME_PHYS), p, motorColors, true);
    btnFree.BackgroundColor = [0.70 0.35 0.00];
    btnZero.BackgroundColor = [0.10 0.65 0.25];
    btnZero.Text = '[✓] CERO REGISTRADO  —  manteniendo L invertida';
    log_('══════════════════════════════');
    log_('  Cero registrado. Controlador activo.');
    log_('  Robot manteniendo posición L invertida.');
    log_('══════════════════════════════');
  end

% ============================================================
%  CINEMÁTICA DIRECTA
% ============================================================
  function enviarCinematicaDirecta()
    st = getSt();
    if ~st.connected; log_('[!] Conecta el ESP32 primero.'); return; end
    q_fw   = [efFK1.Value, efFK2.Value, efFK3.Value];   
    q_phys = q_fw + st.home_q;                          
    
    t1 = deg2rad(q_phys(1)); t2 = deg2rad(q_phys(2)); t3 = deg2rad(q_phys(3));
    
    r  = p.L2*cos(t2) + p.L3*cos(t3+pi/2);
    xc = r*cos(t1)*1000; yc = r*sin(t1)*1000;
    zc = (p.L1 + p.L2*sin(t2) + p.L3*sin(t3+pi/2))*1000;
    
    efX.Value = round(xc,2); efY.Value = round(yc,2); efZ.Value = round(zc,2);
    cmd = sprintf('T,%.2f,%.2f,%.2f', q_fw(1), q_fw(2), q_fw(3));
    writeline(st.port, cmd);
    st.target_q = q_phys;
    setSt(st);
    dibujarRobot(ax3D, deg2rad(q_phys), p, motorColors, false);
    log_(sprintf('>> FK Δθ1=%.1f° Δθ2=%.1f° Δθ3=%.1f°  →  X=%.1f Y=%.1f Z=%.1f mm', ...
      q_fw(1), q_fw(2), q_fw(3), xc, yc, zc));
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
%  TELEMETRÍA
% ============================================================
  function leerTelemetria()
    persistent last_draw_t csv_buf csv_cnt;
    if isempty(last_draw_t); last_draw_t = 0; end
    if isempty(csv_buf); csv_buf = ''; end
    if isempty(csv_cnt); csv_cnt = 0; end
    try
      st = getappdata(fig,'st');
      if ~st.connected || isempty(st.port) || ~isvalid(st.port); return; end
      nb = st.port.NumBytesAvailable;
      if nb == 0; return; end
      raw_all = char(read(st.port, nb, 'uint8'));
    catch; return; end
    
    lines = strsplit(raw_all, char(10));
    for k = 1:numel(lines)
      candidate = strtrim(lines{k});
      if startsWith(candidate, 'FAULT:')
        log_(['[!] ' candidate ' — motor bloqueado. Enviar ZERO o DISARM.']);
      elseif startsWith(candidate, 'LIMIT:')
        log_(['[!] ' candidate ' — setpoint fuera de rango, ajustado al limite.']);
      end
    end
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
    
    csv_buf = [csv_buf, sprintf('%.3f,%.2f,%.2f,%.2f,%.3f,%.3f,%.3f,%d,%d,%d\n', ...
      t_now, vals(1), vals(2), vals(3), vals(4), vals(5), vals(6), ...
      int32(vals(7)), int32(vals(8)), int32(vals(9)))];
    csv_cnt = csv_cnt + 1;
    if csv_cnt >= 50
      fid = fopen('robot_log.csv', 'a');
      if fid ~= -1; fwrite(fid, csv_buf); fclose(fid); end
      csv_buf = ''; csv_cnt = 0;
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
    
    if (t_now - last_draw_t) > 0.04
      last_draw_t = t_now;
      if isvalid(fig)
        q_vis = st.current_q;
        q_vis(2) = -st.current_q(2);
        q_vis(3) = -st.current_q(3);
        q_phys = q_vis + st.home_q;
        dibujarRobot(ax3D, deg2rad(q_phys), p, motorColors, false);
        lblAngulos.Text = sprintf('θ1: %.1f°   θ2: %.1f°   θ3: %.1f°', q_phys(1), q_phys(2), q_phys(3));

        t1=deg2rad(q_phys(1)); t2=deg2rad(q_phys(2)); t3=deg2rad(q_phys(3));
        r_=p.L2*cos(t2)+p.L3*cos(t3+pi/2);
        efX.Value=round(r_*cos(t1)*1000,2);
        efY.Value=round(r_*sin(t1)*1000,2);
        efZ.Value=round((p.L1+p.L2*sin(t2)+p.L3*sin(t3+pi/2))*1000,2);
        
        efFK1.Value=round(st.current_q(1),2);
        efFK2.Value=round(st.current_q(2),2);
        efFK3.Value=round(st.current_q(3),2);
        
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
%  CINEMÁTICA INVERSA (Paralelogramo)
% ============================================================
function [q, errMsg] = ikRobot(pos, p)
  errMsg = '';
  x = pos(1); y = pos(2); z = pos(3);

  q1    = atan2(y, x);
  r     = sqrt(x^2 + y^2);
  z_rel = z - p.L1;

  D_raw = (r^2 + z_rel^2 - p.L2^2 - p.L3^2) / (2 * p.L2 * p.L3);
  if D_raw < -1 || D_raw > 1
    dist = sqrt(r^2 + z_rel^2) * 1000;
    lim  = (p.L2 + p.L3) * 1000;
    errMsg = sprintf('Target fuera de workspace: alcance %.0f mm, límite %.0f mm', dist, lim);
  end
  D = max(-1, min(1, D_raw));

  q3_rel   = atan2(-sqrt(1 - D^2), D);
  q2       = atan2(z_rel, r) - atan2(p.L3*sin(q3_rel), p.L2 + p.L3*cos(q3_rel));
  q3_motor = q2 + q3_rel - pi/2;

  q = [q1, q2, q3_motor];
end

% ============================================================
%  DIBUJO 3D (Paralelogramo + Truco Visual L1)
% ============================================================
function dibujarRobot(ax, q, p, motorColors, resetView)
  % Truco visual para que L1 se vea más largo sin afectar cinemática
  p.L1 = p.L1 + 0.100;
  
  if ~resetView; cv=ax.View; end
  cla(ax); hold(ax,'on');
  
  O=[0;0;0]; P1=[0;0;p.L1];
  P2=P1+[cos(q(1))*cos(q(2))*p.L2; sin(q(1))*cos(q(2))*p.L2; sin(q(2))*p.L2];
  
  % P3 usando cinemática absoluta (paralelogramo)
  P3=P2+[cos(q(1))*cos(q(3)+pi/2)*p.L3; sin(q(1))*cos(q(3)+pi/2)*p.L3; sin(q(3)+pi/2)*p.L3];
  
  pts=[O,P1,P2,P3];
  for k=1:3
    plot3(ax,pts(1,k:k+1),pts(2,k:k+1),pts(3,k:k+1),'-','LineWidth',5,'Color',motorColors{k});
  end
  
  scatter3(ax,pts(1,:),pts(2,:),pts(3,:),80,'w','filled');
  scatter3(ax,P3(1),P3(2),P3(3),120,[1 0.3 0.3],'filled','p');
  plot3(ax,[0 P3(1)],[0 P3(2)],[0 0],'--','Color',[0.3 0.3 0.3],'LineWidth',1);
  
  % Límite Z aumentado a 0.70 para compensar el L1 visual más largo
  ax.XLim=[-0.45 0.45]; ax.YLim=[-0.45 0.45]; ax.ZLim=[0 0.70];
  
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