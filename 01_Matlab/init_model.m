
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% This file is part of the hoverboard-new-firmware-hack-FOC project
% Compared to previouse commutation method, this project implements
% FOC (Field Oriented Control) for BLDC motors with Hall sensors.
% The new control methods offers superior performanace
% compared to previous method featuring:
% >> reduced noise and vibrations
% >> smooth torque output
% >> improved motor efficiency -> lower energy consumption
%
% Author: Emanuel FERU
% Copyright � 2019 Emanuel FERU <aerdronix@gmail.com>
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <http://www.gnu.org/licenses/>.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Clear workspace
close all
clear
clc

% Load model parameters
load BLDCmotorControl_data;
Ts                  = 5e-6;                         % [s] Model sampling time (200 kHz)
Ts_ctrl             = 6e-5;                         % [s] Controller sampling time (~16 kHz)
f_ctrl              = 16e3;                         % [Hz] Controller frequency = 1/Ts_ctrl (16 kHz)
% Ts_ctrl             = 12e-5;                      % [s] Controller sampling time (~8 kHz)

% Motor parameters
n_polePairs         = 15;                           % [-] Number of pole pairs
a_elecPeriod        = 360;                          % [deg] Electrical angle period
a_elecAngle         = 60;                           % [deg] Electrical angle between two Hall sensor changing events
a_mechAngle         = a_elecAngle / n_polePairs;    % [deg] Mechanical angle between two Hall sensor changing events
r_whl               = 6.5 * 2.54 * 1e-2 / 2;        % [m] Wheel radius. Diameter = 6.5 inch (1 inch = 2.54 cm): Speed[kph] = rpm*(pi/30)*r_whl*3.6
i_sca               = 50;                           % [-] [not tunable] Scalling factor A to int16 (50 = 1/0.02)

% Sine/Cosine wave look-up table
res_elecAngle       = 2;
a_elecAngle_XA      = 0:res_elecAngle:360;          % [deg] Electrical angle grid
r_sin_M1            = sin((a_elecAngle_XA + 30)*(pi/180));  % Note: 30 deg shift is to allign it with the Hall sensors position
r_cos_M1            = cos((a_elecAngle_XA + 30)*(pi/180));
% figure
% stairs(a_elecAngle_XA, r_sin_M1); hold on
% stairs(a_elecAngle_XA, r_cos_M1);
% legend('sin','cos');

%% Control Manager
% Control type selection
CTRL_COM            = 0;        % [-] Commutation Control
CTRL_FOC            = 1;        % [-] Field Oriented Control (FOC)
z_ctrlTypSel        = CTRL_FOC; % [-] Control Type Selection (default)

% Control model request
OPEN_MODE           = 0;        % [-] Open mode
VLT_MODE            = 1;        % [-] Voltage mode
SPD_MODE            = 2;        % [-] Speed mode
TRQ_MODE            = 3;        % [-] Torque mode
z_ctrlModReq        = VLT_MODE; % [-] Control Mode Request (default)

%% F01_Estimations
% Position Estimation Parameters
% Hall              = 4*hA + 2*hB + hC
% Hall              = [0 1 2 3 4 5 6 7]
vec_hallToPos       = [0 2 0 1 4 3 5 0];  % [-] Mapping Hall signal to position

% Speed Calculation Parameters
cf_speedCoef        = round(f_ctrl * a_mechAngle * (pi/180) * (30/pi));     % [-] Speed calculation coefficient (factors are due to conversions rpm <-> rad/s)
z_maxCntRst         = 2000;     % [-] Maximum counter value for reset (works also as time-out to detect standing still)
n_commDeacvHi       = 30;       % [rpm] Commutation method deactivation speed high
n_commAcvLo         = 15;       % [rpm] Commutation method activation speed low
dz_cntTrnsDetHi     = 40;       % [-] Counter gradient High for transient behavior detection (used for speed estimation)
dz_cntTrnsDetLo     = 20;       % [-] Counter gradient Low for steady state detection (used for speed estimation)
n_stdStillDet       = 3;        % [rpm] Speed threshold for Stand still detection
cf_currFilt         = 0.12;     % [%] Current filter coefficient [0, 1]. Lower values mean softer filter

%% F02_Diagnostics
b_diagEna           = 1;            % [-] Diagnostics enable flag: 0 = Disabled, 1 = Enabled (default)
t_errQual           = 0.6 * f_ctrl; % [s] Error qualification time
t_errDequal         = 2.0 * f_ctrl; % [s] Error dequalification time
r_errInpTgtThres    = 200;          % [-] Error input target threshold (for "Blocked motor" detection)

%% F04_Field_Oriented_Control

% Current measurement
b_selPhaABCurrMeas  = 1;                % [-] Measured phase currents selection: {iA,iB} = 1 (default); {iB,iC} = 0
dV_openRate         = 1000 * Ts_ctrl;   % [V/s] Rate for voltage cut-off in Open Mode (Sample Time included in the rate)

% Field Weakening
b_fieldWeakEna      = 0;                % [-] Field weakening enable flag: 0 = disable (default), 1 = enable
n_fieldWeakAuthHi   = 200;              % [rpm] Motor speed High for field weakening authorization
n_fieldWeakAuthLo   = 140;              % [rpm] Motor speed Low for field weakening authorization
id_fieldWeak_M1     = [0   0.1   0.3   0.7  1.3  2.1    3  3.8  4.4  4.8   5    5] * i_sca;  % [-] Field weakening current map
r_fieldWeak_XA      = [570 600   630   660  690  720  750  780  810  840 870  900];          % [-] Scaled input target grid
% figure
% plot(r_fieldWeak_XA, id_fieldWeak_M1, '.-'); hold on
% grid

% Q axis control gains
cf_iqKp             = 0.5;              % [-] P gain
cf_iqKi             = 100 * Ts_ctrl;    % [-] I gain
cf_iqKb             = 1000 * Ts_ctrl;   % [-] Back calculation gain for integral anti-windup

% D axis control gains
cf_idKp             = 0.2;              % [-] P gain
cf_idKi             = 60 * Ts_ctrl;     % [-] I gain
cf_idKb             = 1000 * Ts_ctrl;   % [-] Back calculation gain for integral anti-windup

% Speed control gains
cf_nKp              = 1.18;             % [-] P gain
cf_nKi              = 20.4 * Ts_ctrl;   % [-] I gain
cf_nKb              = 1000 * Ts_ctrl;   % [-] Back calculation gain for integral anti-windup

% Limitations
%-------------------------------
% Voltage Limitations
V_margin            = 100;              % [-] Voltage margin to make sure that there is a sufficiently wide pulse for a good phase current measurement
Vd_max              = 1000 - V_margin;
Vq_max_XA           = 0:20:Vd_max;
Vq_max_M1           = sqrt(Vd_max^2 - Vq_max_XA.^2);  % Circle limitations look-up table
% figure
% stairs(Vq_max_XA, Vq_max_M1); legend('V_{max}');

% Speed limitations
cf_nKpLimProt       = 5;                % [-] Speed limit protection gain (only used in VLT_MODE and TRQ_MODE)
n_max               = 800;              % [rpm] Maximum motor speed

% Current Limitations
cf_iqKpLimProt      = 7.2;              % [-] Current limit protection gain (only used in VLT_MODE and SPD_MODE)
cf_iqKiLimProt      = 40.7 * Ts_ctrl;   % [-] Current limit protection integral gain (only used in SPD_MODE)
i_max               = 15;               % [A] Maximum allowed motor current (continuous)
i_max               = i_max * i_sca;
iq_max_XA           = 0:15:i_max;
iq_max_M1           = sqrt(i_max^2 - iq_max_XA.^2);  % Current circle limitations map
% figure
% stairs(iq_max_XA, iq_max_M1); legend('i_{max}');
%-------------------------------

%% F05_Control_Type_Management
% Commutation method
z_commutMap_M1      = [-1 -1  0  1  1  0;   % Phase A
                        1  0 -1 -1  0  1;   % Phase B
                        0  1  1  0 -1 -1];  % Phase C  [-] Commutation method map

disp('---- BLDC_controller: Initialization OK ----');

%% Plot control methods
show_fig            = 0;

if show_fig
    
    sca_factor          = 1000;     % [-] scalling factor (to avoid truncation approximations on integer data type)
    
    % Trapezoidal method
    a_trapElecAngle_XA  = [0 60 120 180 240 300 360];  % [deg] Electrical angle grid
    r_trapPhaA_M1       = sca_factor*[ 1  1  1 -1 -1 -1  1];
    r_trapPhaB_M1       = sca_factor*[-1 -1  1  1  1 -1 -1];
    r_trapPhaC_M1       = sca_factor*[ 1 -1 -1 -1  1  1  1];
    
    % Sinusoidal method
    a_sinElecAngle_XA   = 0:10:360;
    omega               = a_sinElecAngle_XA*(pi/180);
    pha_adv             = 30;       % [deg] Phase advance to mach commands with the Hall position
    r_sinPhaA_M1        = -sca_factor*sin(omega + pha_adv*(pi/180));
    r_sinPhaB_M1        = -sca_factor*sin(omega - 120*(pi/180) + pha_adv*(pi/180));
    r_sinPhaC_M1        = -sca_factor*sin(omega + 120*(pi/180) + pha_adv*(pi/180));
    
    % SVM (Space Vector Modulation) calculation
    SVM_vec             = [r_sinPhaA_M1; r_sinPhaB_M1; r_sinPhaC_M1];
    SVM_min             = min(SVM_vec);
    SVM_max             = max(SVM_vec);
    SVM_sum             = SVM_min + SVM_max;
    SVM_vec             = SVM_vec - 0.5*SVM_sum;
    SVM_vec             = (2/sqrt(3))*SVM_vec;
    
    hall_A = [0 0 0 1 1 1 1] + 4;
    hall_B = [1 1 0 0 0 1 1] + 2;
    hall_C = [0 1 1 1 0 0 0];
    
    color = ['m' 'g' 'b'];
    lw = 1.5;
    figure
    s1 = subplot(221); hold on
    stairs(a_trapElecAngle_XA, hall_A, color(1), 'Linewidth', lw);
    stairs(a_trapElecAngle_XA, hall_B, color(2), 'Linewidth', lw);
    stairs(a_trapElecAngle_XA, hall_C, color(3), 'Linewidth', lw);
    xticks(a_trapElecAngle_XA);
    grid
    yticks(0:5);
    yticklabels({'0','1','0','1','0','1'});
    title('Hall sensors');
    legend('Phase A','Phase B','Phase C','Location','NorthEast');
    
    s2 = subplot(222); hold on
    stairs(a_trapElecAngle_XA, hall_A, color(1), 'Linewidth', lw);
    stairs(a_trapElecAngle_XA, hall_B, color(2), 'Linewidth', lw);
    stairs(a_trapElecAngle_XA, hall_C, color(3), 'Linewidth', lw);
    xticks(a_trapElecAngle_XA);
    grid
    yticks(0:5);
    yticklabels({'0','1','0','1','0','1'});
    title('Hall sensors');
    legend('Phase A','Phase B','Phase C','Location','NorthEast');
    
    s3 = subplot(223); hold on
    stairs(a_trapElecAngle_XA, sca_factor*[z_commutMap_M1(1,:) z_commutMap_M1(1,1)] + 6000, color(1), 'Linewidth', lw);
    stairs(a_trapElecAngle_XA, sca_factor*[z_commutMap_M1(2,:) z_commutMap_M1(2,1)] + 3000, color(2), 'Linewidth', lw);
    stairs(a_trapElecAngle_XA, sca_factor*[z_commutMap_M1(3,:) z_commutMap_M1(3,1)], color(3), 'Linewidth', lw);
    xticks(a_trapElecAngle_XA);
    yticks(-1000:1000:7000);
    yticklabels({'-1000','0','1000','-1000','0','1000','-1000','0','1000'});
    ylim([-1000 7000]);
    grid
    title('Commutation method [0]');
    xlabel('Electrical angle [deg]');
    
    s4 = subplot(224); hold on
    plot(a_sinElecAngle_XA, SVM_vec(1,:), color(1), 'Linewidth', lw);
    plot(a_sinElecAngle_XA, SVM_vec(2,:), color(2), 'Linewidth', lw);
    plot(a_sinElecAngle_XA, SVM_vec(3,:), color(3), 'Linewidth', lw);
    xticks(a_trapElecAngle_XA);
    ylim([-1000 1000])
    grid
    title('FOC method [1]');
    xlabel('Electrical angle [deg]');
    linkaxes([s1 s2 s3 s4],'x');
    xlim([0 360]);
    
end

