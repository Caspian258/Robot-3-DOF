function [] = robotPlot3DOF(theta1, theta2, theta3, l1, l2, l3)
% robotPlot3DOF  –  3-D visualisation of the non-planar RRR arm.
%
%  Kinematic layout  (matches dibujarRobot in RobotController.m)
%  ---------------------------------------------------------------
%  p0 = [0; 0; 0]          world origin (floor)
%  p1 = [0; 0; l1]         top of vertical base column
%  p2 = p1 + l2*[cos(q1)*cos(q2);  sin(q1)*cos(q2);  sin(q2)]
%  p3 = p2 + l3*[cos(q1)*cos(q2+q3); sin(q1)*cos(q2+q3); sin(q2+q3)]
%
%  Inputs
%    theta1, theta2, theta3  joint angles [rad]
%    l1, l2, l3              link lengths [m]  (0.100, 0.205, 0.16569)

%% Forward kinematics
p0 = [0; 0; 0];
p1 = [0; 0; l1];
p2 = p1 + l2*[cos(theta1)*cos(theta2); sin(theta1)*cos(theta2); sin(theta2)];
p3 = p2 + l3*[cos(theta1)*cos(theta2+theta3); ...
               sin(theta1)*cos(theta2+theta3); ...
               sin(theta2+theta3)];

%% Draw
cla; hold on; grid on;

cL1 = [0.15 0.75 0.85];   % cyan   (M1 Base)
cL2 = [0.20 0.85 0.40];   % green  (M2 Shoulder)
cL3 = [1.00 0.60 0.10];   % amber  (M3 Elbow)

plot3([p0(1) p1(1)],[p0(2) p1(2)],[p0(3) p1(3)], '-','LineWidth',5,'Color',cL1)
plot3([p1(1) p2(1)],[p1(2) p2(2)],[p1(3) p2(3)], '-','LineWidth',5,'Color',cL2)
plot3([p2(1) p3(1)],[p2(2) p3(2)],[p2(3) p3(3)], '-','LineWidth',5,'Color',cL3)

pts = [p0, p1, p2, p3];
scatter3(pts(1,:),pts(2,:),pts(3,:), 80,'w','filled')
scatter3(p3(1),p3(2),p3(3), 120,[1 0.3 0.3],'filled','p')
plot3([0 p3(1)],[0 p3(2)],[0 0],'--','Color',[0.4 0.4 0.4],'LineWidth',1)

R = l1+l2+l3;
axis([-R R -R R 0 R+0.05])
xlabel('X (m)'), ylabel('Y (m)'), zlabel('Z (m)')
title('3-DOF Non-Planar Revolute Arm')
legend({'Link 1 (Base)','Link 2 (Shoulder)','Link 3 (Elbow)','End-effector'}, ...
       'Location','best')
view(45,25)
end