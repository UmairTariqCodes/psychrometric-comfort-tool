function psychrometric_interactive()
    % PSYCHROMETRIC_INTERACTIVE - Interactive Psychrometric Chart with GUI
    %
    % This application creates an interactive psychrometric chart where users can:
    %   - Click on any point to get all psychrometric properties
    %   - Enter values manually to calculate properties
    %   - Mark and compare multiple points
    %   - Analyse HVAC processes between two points
    %   - Switch between SI and Imperial units
    %   - Show an ASHRAE 55 comfort zone that responds to clo / met / air speed
    %   - Calculate sensible / latent heat loads
    %   - Stream live readings from a BME280 sensor via Arduino
    %   - Export data and save figures
    %
    % Usage (run from this folder so the +psychro and +bme280 packages are on the path):
    %   psychrometric_interactive()
    %
    % Requirements:
    %   MATLAB R2019b or later (uses serialportlist)
    %   Live Sensor tab only: MATLAB Support Package for Arduino Hardware
    %
    % Structure:
    %   psychrometric_interactive.m  - GUI and callbacks
    %   +psychro/                    - pure psychrometric & comfort calculations (unit-tested)
    %   +bme280/                     - BME280 sensor calibration / compensation
    %
    % Author: Umair Ali Tariq (BEng Mechanical Engineering dissertation, University of Sussex, 2026)
    % License: MIT

    %% Initialize Application Data
    appData = struct();
    appData.unitSystem = 2;  % Default to SI (1=IP, 2=SI)
    appData.pressure = 101325;  % Pa for SI
    appData.TRange = [0 50];  % C for SI
    appData.markedPoints = [];  % Store marked points
    appData.pointCount = 0;
    appData.processLine = [];  % Handle for process line on chart
    appData.showComfortZone = true;  % Show ASHRAE 55 comfort zone by default
    appData.comfortClo = 0.5;        % Clothing insulation (clo) - default summer
    appData.comfortMet = 1.1;        % Metabolic rate (met) - default light office work
    appData.comfortAirVel = 0.1;     % Air velocity (m/s) - default still air
    appData.comfortLockedPoint = 0;  % 0 = follow current click, 1+ = locked to marked point index
    appData.heatLoad = struct('Q_sensible', 0, 'Q_latent', 0, 'Q_total', 0, ...
                              'SHR', 1, 'computed', false, 'unitSystem', 2);

    %% Create Main Figure
    fig = figure('Name', 'Interactive Psychrometric Chart', ...
                 'NumberTitle', 'off', ...
                 'Position', [50 50 1400 800], ...
                 'Color', [0.94 0.94 0.94], ...
                 'MenuBar', 'none', ...
                 'ToolBar', 'figure', ...
                 'CloseRequestFcn', @closeApp);

    %% Create UI Panels
    % Left panel for chart
    chartPanel = uipanel('Parent', fig, ...
                         'Title', 'Psychrometric Chart', ...
                         'FontSize', 12, ...
                         'FontWeight', 'bold', ...
                         'Position', [0.01 0.01 0.68 0.98]);

    % Right panel for controls and results
    controlPanel = uipanel('Parent', fig, ...
                           'Title', 'Properties & Controls', ...
                           'FontSize', 12, ...
                           'FontWeight', 'bold', ...
                           'Position', [0.70 0.01 0.29 0.98]);

    %% Create Chart Axes
    ax = axes('Parent', chartPanel, ...
              'Position', [0.10 0.12 0.85 0.82]);

    %% ===== Unit System Selection (outside tabs) =====
    yPos = 0.95;

    uicontrol('Parent', controlPanel, 'Style', 'text', ...
              'String', 'Unit System:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos-0.02 0.35 0.03], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 10, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    unitGroup = uibuttongroup('Parent', controlPanel, ...
                              'Units', 'normalized', ...
                              'Position', [0.40 yPos-0.03 0.55 0.04], ...
                              'SelectionChangedFcn', @unitChanged, ...
                              'BackgroundColor', [0.94 0.94 0.94]);

    uicontrol('Parent', unitGroup, 'Style', 'radiobutton', ...
              'String', 'SI (Metric)', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.1 0.48 0.8], ...
              'Tag', 'SI', 'Value', 1, ...
              'BackgroundColor', [0.94 0.94 0.94]);

    uicontrol('Parent', unitGroup, 'Style', 'radiobutton', ...
              'String', 'Imperial', ...
              'Units', 'normalized', ...
              'Position', [0.52 0.1 0.46 0.8], ...
              'Tag', 'IP', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    %% ===== Tab Group =====
    tabGroup = uitabgroup('Parent', controlPanel, ...
                          'Units', 'normalized', ...
                          'Position', [0.02 0.05 0.96 0.86]);

    tab1 = uitab('Parent', tabGroup, 'Title', 'Point Analysis');
    tab2 = uitab('Parent', tabGroup, 'Title', 'Process Analysis');
    tab3 = uitab('Parent', tabGroup, 'Title', 'Comfort Zone');
    tab4 = uitab('Parent', tabGroup, 'Title', 'Heat Load');
    tab5 = uitab('Parent', tabGroup, 'Title', 'Live Sensor');

    % Reorder: Comfort Zone, Point Analysis, Heat Load, Process Analysis, Live Sensor
    tabGroup.Children = tabGroup.Children([3 1 4 2 5]);
    tabGroup.SelectedTab = tab3;

    %% ===== TAB 1: Point Analysis =====
    yPos = 0.96;

    % Instructions
    uicontrol('Parent', tab1, 'Style', 'text', ...
              'String', 'Click on chart to select a point', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos-0.03 0.90 0.03], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 10, 'ForegroundColor', [0 0.4 0.8], ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.05;

    % Separator line
    uicontrol('Parent', tab1, 'Style', 'text', ...
              'String', '------- Selected Point -------', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.025], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.035;

    % Results Display Panel
    resultsPanel = uipanel('Parent', tab1, ...
                           'Title', '', ...
                           'Position', [0.03 yPos-0.42 0.94 0.44], ...
                           'BackgroundColor', [1 1 1]);

    % Property labels and values
    properties = {'Dry-Bulb Temperature:', 'T_db';
                  'Humidity Ratio:', 'W';
                  'Relative Humidity:', 'RH';
                  'Wet-Bulb Temperature:', 'T_wb';
                  'Dew Point Temperature:', 'T_dp';
                  'Specific Enthalpy:', 'h';
                  'Specific Volume:', 'v';
                  'Vapour Pressure:', 'P_v';
                  'Saturation Pressure:', 'P_ws'};

    propHandles = struct();
    for i = 1:size(properties, 1)
        yp = 0.95 - (i-1)*0.105;

        uicontrol('Parent', resultsPanel, 'Style', 'text', ...
                  'String', properties{i,1}, ...
                  'Units', 'normalized', ...
                  'Position', [0.03 yp-0.02 0.50 0.08], ...
                  'HorizontalAlignment', 'left', ...
                  'FontSize', 9, ...
                  'BackgroundColor', [1 1 1]);

        propHandles.(properties{i,2}) = uicontrol('Parent', resultsPanel, ...
                  'Style', 'text', ...
                  'String', '---', ...
                  'Units', 'normalized', ...
                  'Position', [0.52 yp-0.02 0.45 0.08], ...
                  'HorizontalAlignment', 'right', ...
                  'FontSize', 9, 'FontWeight', 'bold', ...
                  'ForegroundColor', [0 0.3 0.6], ...
                  'BackgroundColor', [1 1 1]);
    end

    yPos = yPos - 0.46;

    % Separator
    uicontrol('Parent', tab1, 'Style', 'text', ...
              'String', '------- Manual Input -------', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.025], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.035;

    % First Property Dropdown
    uicontrol('Parent', tab1, 'Style', 'text', ...
              'String', 'Property 1:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.22 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    firstPropDropdown = uicontrol('Parent', tab1, 'Style', 'popupmenu', ...
              'String', {'Dry-Bulb Temp', 'Wet-Bulb Temp', 'Dew Point Temp', 'Humidity Ratio', 'Enthalpy', 'Rel. Humidity'}, ...
              'Units', 'normalized', ...
              'Position', [0.28 yPos-0.005 0.40 0.03], ...
              'FontSize', 9, ...
              'Value', 1, ...
              'Callback', @propDropdownChanged, ...
              'Tag', 'firstPropDropdown');

    firstPropInput = uicontrol('Parent', tab1, 'Style', 'edit', ...
              'String', '25', ...
              'Units', 'normalized', ...
              'Position', [0.70 yPos-0.005 0.18 0.03], ...
              'FontSize', 9, ...
              'Tag', 'firstPropInput');

    firstPropUnit = uicontrol('Parent', tab1, 'Style', 'text', ...
              'String', 'C', ...
              'Units', 'normalized', ...
              'Position', [0.89 yPos 0.10 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 9, ...
              'BackgroundColor', [0.94 0.94 0.94], ...
              'Tag', 'firstPropUnit');

    yPos = yPos - 0.04;

    % Second Property Dropdown
    uicontrol('Parent', tab1, 'Style', 'text', ...
              'String', 'Property 2:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.22 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    secondPropDropdown = uicontrol('Parent', tab1, 'Style', 'popupmenu', ...
              'String', {'Dry-Bulb Temp', 'Wet-Bulb Temp', 'Dew Point Temp', 'Humidity Ratio', 'Enthalpy', 'Rel. Humidity'}, ...
              'Units', 'normalized', ...
              'Position', [0.28 yPos-0.005 0.40 0.03], ...
              'FontSize', 9, ...
              'Value', 6, ...
              'Callback', @propDropdownChanged, ...
              'Tag', 'secondPropDropdown');

    secondPropInput = uicontrol('Parent', tab1, 'Style', 'edit', ...
              'String', '50', ...
              'Units', 'normalized', ...
              'Position', [0.70 yPos-0.005 0.18 0.03], ...
              'FontSize', 9, ...
              'Tag', 'secondPropInput');

    secondPropUnit = uicontrol('Parent', tab1, 'Style', 'text', ...
              'String', '%', ...
              'Units', 'normalized', ...
              'Position', [0.89 yPos 0.10 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 9, ...
              'BackgroundColor', [0.94 0.94 0.94], ...
              'Tag', 'secondPropUnit');

    yPos = yPos - 0.04;

    % Calculate Button
    uicontrol('Parent', tab1, 'Style', 'pushbutton', ...
              'String', 'Calculate Properties', ...
              'Units', 'normalized', ...
              'Position', [0.10 yPos 0.80 0.035], ...
              'FontSize', 10, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.2 0.6 0.2], ...
              'ForegroundColor', [1 1 1], ...
              'Callback', @calculateFromInput);

    yPos = yPos - 0.045;

    % Mark Point Button
    uicontrol('Parent', tab1, 'Style', 'pushbutton', ...
              'String', 'Mark Current Point', ...
              'Units', 'normalized', ...
              'Position', [0.10 yPos 0.38 0.035], ...
              'FontSize', 9, ...
              'BackgroundColor', [0.3 0.5 0.8], ...
              'ForegroundColor', [1 1 1], ...
              'Callback', @markPoint);

    uicontrol('Parent', tab1, 'Style', 'pushbutton', ...
              'String', 'Clear Marks', ...
              'Units', 'normalized', ...
              'Position', [0.52 yPos 0.38 0.035], ...
              'FontSize', 9, ...
              'BackgroundColor', [0.8 0.3 0.3], ...
              'ForegroundColor', [1 1 1], ...
              'Callback', @clearMarks);

    yPos = yPos - 0.045;

    % Separator
    uicontrol('Parent', tab1, 'Style', 'text', ...
              'String', '------- Actions -------', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.025], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.04;

    % Export Button
    uicontrol('Parent', tab1, 'Style', 'pushbutton', ...
              'String', 'Export Data', ...
              'Units', 'normalized', ...
              'Position', [0.10 yPos 0.38 0.035], ...
              'FontSize', 9, ...
              'BackgroundColor', [0.5 0.5 0.5], ...
              'ForegroundColor', [1 1 1], ...
              'Callback', @exportData);

    uicontrol('Parent', tab1, 'Style', 'pushbutton', ...
              'String', 'Save Chart', ...
              'Units', 'normalized', ...
              'Position', [0.52 yPos 0.38 0.035], ...
              'FontSize', 9, ...
              'BackgroundColor', [0.5 0.5 0.5], ...
              'ForegroundColor', [1 1 1], ...
              'Callback', @saveChart);

    %% ===== TAB 2: Process Analysis =====
    yPos = 0.96;

    uicontrol('Parent', tab2, 'Style', 'text', ...
              'String', 'Select two marked points to analyse an HVAC process', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos-0.03 0.90 0.03], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 9, 'ForegroundColor', [0 0.4 0.8], ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.06;

    % Point A selector
    uicontrol('Parent', tab2, 'Style', 'text', ...
              'String', 'Point A:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.20 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 10, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    pointADropdown = uicontrol('Parent', tab2, 'Style', 'popupmenu', ...
              'String', {'(No marked points)'}, ...
              'Units', 'normalized', ...
              'Position', [0.28 yPos-0.005 0.67 0.03], ...
              'FontSize', 9, ...
              'Tag', 'pointADropdown');

    yPos = yPos - 0.045;

    % Point B selector
    uicontrol('Parent', tab2, 'Style', 'text', ...
              'String', 'Point B:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.20 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 10, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    pointBDropdown = uicontrol('Parent', tab2, 'Style', 'popupmenu', ...
              'String', {'(No marked points)'}, ...
              'Units', 'normalized', ...
              'Position', [0.28 yPos-0.005 0.67 0.03], ...
              'FontSize', 9, ...
              'Tag', 'pointBDropdown');

    yPos = yPos - 0.045;

    % --- Room / Building Inputs ---
    uicontrol('Parent', tab2, 'Style', 'text', ...
              'String', '--- Room / Building ---', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.025], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.04;

    % Room Volume input
    uicontrol('Parent', tab2, 'Style', 'text', ...
              'String', 'Room Volume:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.28 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    roomVolumeInput = uicontrol('Parent', tab2, 'Style', 'edit', ...
              'String', '100', ...
              'Units', 'normalized', ...
              'Position', [0.35 yPos-0.005 0.30 0.03], ...
              'FontSize', 9, ...
              'Tag', 'roomVolumeInput');

    roomVolumeUnit = uicontrol('Parent', tab2, 'Style', 'text', ...
              'String', 'm^3', ...
              'Units', 'normalized', ...
              'Position', [0.67 yPos 0.28 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 9, ...
              'BackgroundColor', [0.94 0.94 0.94], ...
              'Tag', 'roomVolumeUnit');

    yPos = yPos - 0.04;

    % ACH (Air Changes per Hour) input
    uicontrol('Parent', tab2, 'Style', 'text', ...
              'String', 'Air Changes/hr:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.28 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    achInput = uicontrol('Parent', tab2, 'Style', 'edit', ...
              'String', '6', ...
              'Units', 'normalized', ...
              'Position', [0.35 yPos-0.005 0.30 0.03], ...
              'FontSize', 9, ...
              'Tag', 'achInput');

    uicontrol('Parent', tab2, 'Style', 'text', ...
              'String', 'ACH', ...
              'Units', 'normalized', ...
              'Position', [0.67 yPos 0.28 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 9, ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.04;

    % Computed flow rates (read-only display)
    uicontrol('Parent', tab2, 'Style', 'text', ...
              'String', 'Vol. Flow Rate:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.28 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 8, ...
              'BackgroundColor', [0.94 0.94 0.94]);

    volFlowDisplay = uicontrol('Parent', tab2, 'Style', 'text', ...
              'String', '---', ...
              'Units', 'normalized', ...
              'Position', [0.35 yPos 0.60 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 8, 'FontWeight', 'bold', ...
              'ForegroundColor', [0 0.3 0.6], ...
              'BackgroundColor', [0.94 0.94 0.94], ...
              'Tag', 'volFlowDisplay');

    yPos = yPos - 0.03;

    uicontrol('Parent', tab2, 'Style', 'text', ...
              'String', 'Mass Flow Rate:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.28 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 8, ...
              'BackgroundColor', [0.94 0.94 0.94]);

    massFlowDisplay = uicontrol('Parent', tab2, 'Style', 'text', ...
              'String', '---', ...
              'Units', 'normalized', ...
              'Position', [0.35 yPos 0.60 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 8, 'FontWeight', 'bold', ...
              'ForegroundColor', [0 0.3 0.6], ...
              'BackgroundColor', [0.94 0.94 0.94], ...
              'Tag', 'massFlowDisplay');

    yPos = yPos - 0.035;

    % Bypass Factor input
    uicontrol('Parent', tab2, 'Style', 'text', ...
              'String', 'Bypass Factor (BF):', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.28 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    bypassFactorInput = uicontrol('Parent', tab2, 'Style', 'edit', ...
              'String', '0.10', ...
              'Units', 'normalized', ...
              'Position', [0.35 yPos-0.005 0.30 0.03], ...
              'FontSize', 9, ...
              'Tag', 'bypassFactorInput');

    uicontrol('Parent', tab2, 'Style', 'text', ...
              'String', '(0 = ideal coil, 0.2 = poor)', ...
              'Units', 'normalized', ...
              'Position', [0.67 yPos 0.32 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'ForegroundColor', [0.4 0.4 0.4], ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.035;

    % Keep hidden flowRateInput for backward compatibility in analyseProcess
    flowRateInput = uicontrol('Parent', tab2, 'Style', 'edit', ...
              'String', '1.0', ...
              'Units', 'normalized', ...
              'Position', [0 0 0.01 0.01], ...
              'Visible', 'off', ...
              'Tag', 'flowRateInput');

    flowRateUnit = uicontrol('Parent', tab2, 'Style', 'text', ...
              'String', 'kg/s', ...
              'Units', 'normalized', ...
              'Position', [0 0 0.01 0.01], ...
              'Visible', 'off', ...
              'Tag', 'flowRateUnit');

    % Analyse Process Button
    uicontrol('Parent', tab2, 'Style', 'pushbutton', ...
              'String', 'Analyse Process', ...
              'Units', 'normalized', ...
              'Position', [0.10 yPos 0.80 0.035], ...
              'FontSize', 10, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.2 0.6 0.2], ...
              'ForegroundColor', [1 1 1], ...
              'Callback', @analyseProcess);

    yPos = yPos - 0.04;

    % Process Results Separator
    uicontrol('Parent', tab2, 'Style', 'text', ...
              'String', '------- Process Results -------', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.025], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.03;

    % Process results panel
    processPanel = uipanel('Parent', tab2, ...
                           'Title', '', ...
                           'Position', [0.03 yPos-0.52 0.94 0.54], ...
                           'BackgroundColor', [1 1 1]);

    % Process result labels
    processProps = {'Process Type:', 'procType';
                    'Temp Change (dT):', 'dT';
                    'Humidity Change (dW):', 'dW';
                    'Enthalpy Change (dh):', 'dh';
                    'Sensible Heat (Qs):', 'Qs';
                    'Latent Heat (Ql):', 'Ql';
                    'Total Heat (Qt):', 'Qt';
                    'Sensible Heat Ratio:', 'SHR';
                    'Moisture Rate:', 'mw';
                    'Supply Air Temp (A):', 'Ta';
                    'Supply Air Temp (B):', 'Tb';
                    'Apparatus Dew Point:', 'ADP';
                    'Reheat Load:', 'Qreheat';
                    '--- Equipment Sizing ---', 'sizingSep';
                    'Vol. Flow (Inlet):', 'VdotA';
                    'Vol. Flow (Outlet):', 'VdotB';
                    'Process Capacity:', 'reqCapacity';
                    'Building Load (Tab 4):', 'bldgLoad';
                    'Combined Capacity:', 'combinedCapacity';
                    'Design Capacity (x1.15):', 'designCapacity';
                    'Moisture Removal:', 'moistureRate';
                    'Equipment Type:', 'equipType'};

    procHandles = struct();
    nProps = size(processProps, 1);
    rowHeight = 0.96 / nProps;
    for i = 1:nProps
        yp = 0.97 - (i-1)*rowHeight;

        % Separator row gets special styling
        if strcmp(processProps{i,2}, 'sizingSep')
            uicontrol('Parent', processPanel, 'Style', 'text', ...
                      'String', processProps{i,1}, ...
                      'Units', 'normalized', ...
                      'Position', [0.03 yp-0.015 0.94 0.04], ...
                      'HorizontalAlignment', 'center', ...
                      'FontSize', 8, 'FontWeight', 'bold', ...
                      'ForegroundColor', [0.4 0.4 0.4], ...
                      'BackgroundColor', [1 1 1]);
            procHandles.(processProps{i,2}) = uicontrol('Parent', processPanel, ...
                      'Style', 'text', 'String', '', ...
                      'Units', 'normalized', ...
                      'Position', [0 0 0.01 0.01], 'Visible', 'off');
        else
            uicontrol('Parent', processPanel, 'Style', 'text', ...
                      'String', processProps{i,1}, ...
                      'Units', 'normalized', ...
                      'Position', [0.03 yp-0.015 0.50 0.04], ...
                      'HorizontalAlignment', 'left', ...
                      'FontSize', 8, ...
                      'BackgroundColor', [1 1 1]);

            procHandles.(processProps{i,2}) = uicontrol('Parent', processPanel, ...
                      'Style', 'text', ...
                      'String', '---', ...
                      'Units', 'normalized', ...
                      'Position', [0.52 yp-0.015 0.45 0.04], ...
                      'HorizontalAlignment', 'right', ...
                      'FontSize', 8, 'FontWeight', 'bold', ...
                      'ForegroundColor', [0 0.3 0.6], ...
                      'BackgroundColor', [1 1 1]);
        end
    end

    yPos = yPos - 0.56;

    % Draw/Clear Process buttons
    uicontrol('Parent', tab2, 'Style', 'pushbutton', ...
              'String', 'Draw Process', ...
              'Units', 'normalized', ...
              'Position', [0.10 yPos 0.38 0.035], ...
              'FontSize', 9, ...
              'BackgroundColor', [0.3 0.5 0.8], ...
              'ForegroundColor', [1 1 1], ...
              'Callback', @drawProcess);

    uicontrol('Parent', tab2, 'Style', 'pushbutton', ...
              'String', 'Clear Process', ...
              'Units', 'normalized', ...
              'Position', [0.52 yPos 0.38 0.035], ...
              'FontSize', 9, ...
              'BackgroundColor', [0.8 0.3 0.3], ...
              'ForegroundColor', [1 1 1], ...
              'Callback', @clearProcess);

    %% ===== TAB 3: Comfort Zone =====
    yPos = 0.96;

    % Show/Hide toggle
    comfortZoneCheckbox = uicontrol('Parent', tab3, 'Style', 'checkbox', ...
              'String', 'Show ASHRAE 55 Comfort Zone', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos-0.02 0.90 0.03], ...
              'FontSize', 10, 'FontWeight', 'bold', ...
              'Value', 1, ...
              'BackgroundColor', [0.94 0.94 0.94], ...
              'Callback', @toggleComfortZone, ...
              'Tag', 'comfortZoneCheckbox');

    yPos = yPos - 0.04;

    % Lock to Point
    uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', 'Assess Point:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.28 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    comfortPointDropdown = uicontrol('Parent', tab3, 'Style', 'popupmenu', ...
              'String', {'Current click'}, ...
              'Units', 'normalized', ...
              'Position', [0.34 yPos-0.005 0.61 0.03], ...
              'FontSize', 8, ...
              'Callback', @comfortPointChanged, ...
              'Tag', 'comfortPointDropdown');

    yPos = yPos - 0.045;

    % Separator - Clothing
    uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', '------- Clothing Insulation -------', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.025], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.04;

    % Clo slider label
    uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', 'Clo Value:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.22 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    cloInput = uicontrol('Parent', tab3, 'Style', 'edit', ...
              'String', '0.5', ...
              'Units', 'normalized', ...
              'Position', [0.28 yPos-0.005 0.15 0.03], ...
              'FontSize', 9, ...
              'Callback', @cloInputChanged, ...
              'Tag', 'cloInput');

    uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', 'clo', ...
              'Units', 'normalized', ...
              'Position', [0.44 yPos 0.10 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 9, ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.04;

    % Clo slider
    cloSlider = uicontrol('Parent', tab3, 'Style', 'slider', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.025], ...
              'Min', 0.3, 'Max', 1.5, 'Value', 0.5, ...
              'SliderStep', [0.1/1.2, 0.2/1.2], ...
              'Callback', @cloSliderChanged, ...
              'Tag', 'cloSlider');

    yPos = yPos - 0.025;

    % Slider range labels
    uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', '0.3', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.10 0.02], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', '1.5', ...
              'Units', 'normalized', ...
              'Position', [0.85 yPos 0.10 0.02], ...
              'HorizontalAlignment', 'right', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.03;

    % Clothing description
    cloDescription = uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', 'Light trousers + short-sleeve shirt', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.025], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 8, 'FontAngle', 'italic', ...
              'ForegroundColor', [0.3 0.3 0.3], ...
              'BackgroundColor', [0.94 0.94 0.94], ...
              'Tag', 'cloDescription');

    yPos = yPos - 0.035;

    % Preset buttons
    uicontrol('Parent', tab3, 'Style', 'pushbutton', ...
              'String', 'Summer (0.5)', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.28 0.03], ...
              'FontSize', 8, ...
              'BackgroundColor', [1.0 0.85 0.7], ...
              'Callback', {@cloPreset, 0.5});

    uicontrol('Parent', tab3, 'Style', 'pushbutton', ...
              'String', 'Typical (0.7)', ...
              'Units', 'normalized', ...
              'Position', [0.36 yPos 0.28 0.03], ...
              'FontSize', 8, ...
              'BackgroundColor', [0.85 0.9 0.85], ...
              'Callback', {@cloPreset, 0.7});

    uicontrol('Parent', tab3, 'Style', 'pushbutton', ...
              'String', 'Winter (1.0)', ...
              'Units', 'normalized', ...
              'Position', [0.67 yPos 0.28 0.03], ...
              'FontSize', 8, ...
              'BackgroundColor', [0.7 0.85 1.0], ...
              'Callback', {@cloPreset, 1.0});

    yPos = yPos - 0.05;

    % Separator - Metabolic Rate
    uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', '------- Metabolic Rate -------', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.025], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.04;

    % Met input
    uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', 'Met Value:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.22 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    metInput = uicontrol('Parent', tab3, 'Style', 'edit', ...
              'String', '1.1', ...
              'Units', 'normalized', ...
              'Position', [0.28 yPos-0.005 0.15 0.03], ...
              'FontSize', 9, ...
              'Callback', @metInputChanged, ...
              'Tag', 'metInput');

    uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', 'met', ...
              'Units', 'normalized', ...
              'Position', [0.44 yPos 0.10 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 9, ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.04;

    % Met slider
    metSlider = uicontrol('Parent', tab3, 'Style', 'slider', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.025], ...
              'Min', 1.0, 'Max', 2.0, 'Value', 1.1, ...
              'SliderStep', [0.1/1.0, 0.2/1.0], ...
              'Callback', @metSliderChanged, ...
              'Tag', 'metSlider');

    yPos = yPos - 0.025;

    % Slider range labels
    uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', '1.0', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.10 0.02], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', '2.0', ...
              'Units', 'normalized', ...
              'Position', [0.85 yPos 0.10 0.02], ...
              'HorizontalAlignment', 'right', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.03;

    % Met preset dropdown
    uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', 'Activity:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.18 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 9, ...
              'BackgroundColor', [0.94 0.94 0.94]);

    metPresetDropdown = uicontrol('Parent', tab3, 'Style', 'popupmenu', ...
              'String', {'Seated, relaxed (1.0)', 'Light office work (1.1)', ...
                         'Standing, relaxed (1.2)', 'Light activity (1.3)', ...
                         'Medium activity (1.6)', 'Walking slowly (2.0)'}, ...
              'Units', 'normalized', ...
              'Position', [0.24 yPos-0.005 0.71 0.03], ...
              'FontSize', 8, ...
              'Value', 2, ...
              'Callback', @metPresetChanged, ...
              'Tag', 'metPresetDropdown');

    yPos = yPos - 0.05;

    % Separator - Air Velocity
    uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', '------- Air Velocity -------', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.025], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.04;

    % Air velocity input
    uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', 'Air Speed:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.22 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    airVelInput = uicontrol('Parent', tab3, 'Style', 'edit', ...
              'String', '0.1', ...
              'Units', 'normalized', ...
              'Position', [0.28 yPos-0.005 0.15 0.03], ...
              'FontSize', 9, ...
              'Callback', @airVelInputChanged, ...
              'Tag', 'airVelInput');

    airVelUnit = uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', 'm/s', ...
              'Units', 'normalized', ...
              'Position', [0.44 yPos 0.10 0.025], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 9, ...
              'BackgroundColor', [0.94 0.94 0.94], ...
              'Tag', 'airVelUnit');

    yPos = yPos - 0.04;

    % Air velocity slider
    airVelSlider = uicontrol('Parent', tab3, 'Style', 'slider', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.025], ...
              'Min', 0.1, 'Max', 1.2, 'Value', 0.1, ...
              'SliderStep', [0.1/1.1, 0.3/1.1], ...
              'Callback', @airVelSliderChanged, ...
              'Tag', 'airVelSlider');

    yPos = yPos - 0.025;

    % Slider range labels
    uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', '0.1', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.10 0.02], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', '1.2', ...
              'Units', 'normalized', ...
              'Position', [0.85 yPos 0.10 0.02], ...
              'HorizontalAlignment', 'right', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.045;

    % Separator - Comfort Assessment
    uicontrol('Parent', tab3, 'Style', 'text', ...
              'String', '------- Comfort Assessment -------', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.025], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    yPos = yPos - 0.03;

    % Comfort results panel
    comfortPanel = uipanel('Parent', tab3, ...
                           'Title', '', ...
                           'Position', [0.03 yPos-0.22 0.94 0.24], ...
                           'BackgroundColor', [1 1 1]);

    comfortResults = struct();

    comfortLabels = {'Comfort Zone Range:', 'czRange';
                     'Current Point Status:', 'czStatus';
                     'Operative Temp (To):', 'czTo';
                     'PMV Estimate:', 'czPMV';
                     'PPD Estimate:', 'czPPD'};

    for i = 1:size(comfortLabels, 1)
        yp = 0.85 - (i-1)*0.19;

        uicontrol('Parent', comfortPanel, 'Style', 'text', ...
                  'String', comfortLabels{i,1}, ...
                  'Units', 'normalized', ...
                  'Position', [0.03 yp-0.02 0.48 0.15], ...
                  'HorizontalAlignment', 'left', ...
                  'FontSize', 8, ...
                  'BackgroundColor', [1 1 1]);

        comfortResults.(comfortLabels{i,2}) = uicontrol('Parent', comfortPanel, ...
                  'Style', 'text', ...
                  'String', '---', ...
                  'Units', 'normalized', ...
                  'Position', [0.50 yp-0.02 0.47 0.15], ...
                  'HorizontalAlignment', 'right', ...
                  'FontSize', 8, 'FontWeight', 'bold', ...
                  'ForegroundColor', [0 0.3 0.6], ...
                  'BackgroundColor', [1 1 1]);
    end

    %% ===== TAB 4: Heat Load Calculation =====
    yPos = 0.97;

    % --- Section 1: Design Conditions ---
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', '--- Design Conditions ---', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos-0.02 0.90 0.025], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);
    yPos = yPos - 0.04;

    % Load Type dropdown
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'Load Type:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.28 0.022], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 8, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlLoadType = uicontrol('Parent', tab4, 'Style', 'popupmenu', ...
              'String', {'Cooling (CLTD)', 'Heating (UA*dT)'}, ...
              'Units', 'normalized', ...
              'Position', [0.35 yPos-0.005 0.60 0.028], ...
              'FontSize', 8, ...
              'Tag', 'hlLoadType');
    yPos = yPos - 0.035;

    % Outdoor source dropdown
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'Outdoor:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.15 0.022], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 8, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlOutdoorSource = uicontrol('Parent', tab4, 'Style', 'popupmenu', ...
              'String', {'Manual Input', 'Live Sensor Data'}, ...
              'Units', 'normalized', ...
              'Position', [0.20 yPos-0.003 0.75 0.025], ...
              'FontSize', 8, ...
              'Callback', @hlSourceChangedCallback, ...
              'Tag', 'hlOutdoorSource');
    yPos = yPos - 0.030;

    % Outdoor Design Temp
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'Temp:', ...
              'Units', 'normalized', ...
              'Position', [0.10 yPos 0.15 0.022], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 8, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlOutdoorTemp = uicontrol('Parent', tab4, 'Style', 'edit', ...
              'String', '35', ...
              'Units', 'normalized', ...
              'Position', [0.25 yPos-0.003 0.18 0.025], ...
              'FontSize', 8, 'Tag', 'hlOutdoorTemp');
    hlOutdoorTempUnit = uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'C', ...
              'Units', 'normalized', ...
              'Position', [0.44 yPos 0.06 0.022], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 8, ...
              'BackgroundColor', [0.94 0.94 0.94]);

    % Outdoor RH
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'RH:', ...
              'Units', 'normalized', ...
              'Position', [0.52 yPos 0.10 0.022], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 8, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlOutdoorRH = uicontrol('Parent', tab4, 'Style', 'edit', ...
              'String', '40', ...
              'Units', 'normalized', ...
              'Position', [0.62 yPos-0.003 0.13 0.025], ...
              'FontSize', 8, 'Tag', 'hlOutdoorRH');
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', '%', ...
              'Units', 'normalized', ...
              'Position', [0.76 yPos 0.06 0.022], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 8, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    yPos = yPos - 0.032;

    % Indoor source dropdown
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'Indoor:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.15 0.022], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 8, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlIndoorSource = uicontrol('Parent', tab4, 'Style', 'popupmenu', ...
              'String', {'Manual Input', 'Live Sensor Data'}, ...
              'Units', 'normalized', ...
              'Position', [0.20 yPos-0.003 0.75 0.025], ...
              'FontSize', 8, ...
              'Callback', @hlSourceChangedCallback, ...
              'Tag', 'hlIndoorSource');
    yPos = yPos - 0.030;

    % Indoor Design Temp
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'Temp:', ...
              'Units', 'normalized', ...
              'Position', [0.10 yPos 0.15 0.022], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 8, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlIndoorTemp = uicontrol('Parent', tab4, 'Style', 'edit', ...
              'String', '24', ...
              'Units', 'normalized', ...
              'Position', [0.25 yPos-0.003 0.18 0.025], ...
              'FontSize', 8, 'Tag', 'hlIndoorTemp');
    hlIndoorTempUnit = uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'C', ...
              'Units', 'normalized', ...
              'Position', [0.44 yPos 0.06 0.022], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 8, ...
              'BackgroundColor', [0.94 0.94 0.94]);

    % Indoor RH
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'RH:', ...
              'Units', 'normalized', ...
              'Position', [0.52 yPos 0.10 0.022], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 8, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlIndoorRH = uicontrol('Parent', tab4, 'Style', 'edit', ...
              'String', '50', ...
              'Units', 'normalized', ...
              'Position', [0.62 yPos-0.003 0.13 0.025], ...
              'FontSize', 8, 'Tag', 'hlIndoorRH');
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', '%', ...
              'Units', 'normalized', ...
              'Position', [0.76 yPos 0.06 0.022], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 8, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    yPos = yPos - 0.032;

    % CLTD auto-correct checkbox
    hlCLTDAutoCorrect = uicontrol('Parent', tab4, 'Style', 'checkbox', ...
              'String', 'Auto-correct CLTD (adj. for design temps)', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.025], ...
              'FontSize', 7, 'Value', 1, ...
              'BackgroundColor', [0.94 0.94 0.94], ...
              'Tag', 'hlCLTDAutoCorrect');
    yPos = yPos - 0.03;

    % --- Section 2: Building Envelope (Per-Wall Table) ---
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', '--- Building Envelope ---', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.022], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);
    yPos = yPos - 0.025;

    % Envelope table headers
    envColHeaders = {'U wall', 'A wall', 'CLTD', 'A glass', 'U glass', 'SHGC', 'I solar'};
    envColWidths = 'auto';
    envRowNames = {'N', 'E', 'S', 'W', 'Roof'};

    % Default data: [U-wall, Area, CLTD, GlassArea, GlassU, SHGC, SolarRad]
    envDefaultData = {0.50, 20, 7,  4, 3.0, 0.40, 110;   % North
                      0.50, 20, 12, 4, 3.0, 0.40, 600;   % East
                      0.50, 20, 10, 4, 3.0, 0.40, 480;   % South
                      0.50, 20, 12, 4, 3.0, 0.40, 600;   % West
                      0.35, 40, 18, 0, 3.0, 0.40, 900};  % Roof

    hlEnvelopeTable = uitable('Parent', tab4, ...
              'Units', 'normalized', ...
              'Position', [0.02 yPos-0.18 0.96 0.19], ...
              'Data', envDefaultData, ...
              'ColumnName', envColHeaders, ...
              'RowName', envRowNames, ...
              'ColumnEditable', true(1, 7), ...
              'ColumnFormat', {'numeric','numeric','numeric','numeric','numeric','numeric','numeric'}, ...
              'FontSize', 8, ...
              'Tag', 'hlEnvelopeTable');
    yPos = yPos - 0.195;

    % Unit labels for envelope table
    hlEnvUnitLabel = uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'U=W/m2K | A=m2 | CLTD=C | I solar=W/m2', ...
              'Units', 'normalized', ...
              'Position', [0.02 yPos 0.96 0.018], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 6, 'ForegroundColor', [0.4 0.4 0.4], ...
              'BackgroundColor', [0.94 0.94 0.94]);
    yPos = yPos - 0.02;

    % Optional floor checkbox + inputs
    hlIncludeFloor = uicontrol('Parent', tab4, 'Style', 'checkbox', ...
              'String', 'Include Floor:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.22 0.022], ...
              'FontSize', 7, 'Value', 0, ...
              'BackgroundColor', [0.94 0.94 0.94], ...
              'Tag', 'hlIncludeFloor');
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'U:', ...
              'Units', 'normalized', ...
              'Position', [0.27 yPos 0.05 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlFloorU = uicontrol('Parent', tab4, 'Style', 'edit', ...
              'String', '0.50', ...
              'Units', 'normalized', ...
              'Position', [0.32 yPos-0.002 0.10 0.022], ...
              'FontSize', 7, 'Tag', 'hlFloorU');
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'A:', ...
              'Units', 'normalized', ...
              'Position', [0.43 yPos 0.05 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlFloorArea = uicontrol('Parent', tab4, 'Style', 'edit', ...
              'String', '40', ...
              'Units', 'normalized', ...
              'Position', [0.48 yPos-0.002 0.10 0.022], ...
              'FontSize', 7, 'Tag', 'hlFloorArea');
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'Tgnd:', ...
              'Units', 'normalized', ...
              'Position', [0.59 yPos 0.08 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlFloorTgnd = uicontrol('Parent', tab4, 'Style', 'edit', ...
              'String', '18', ...
              'Units', 'normalized', ...
              'Position', [0.67 yPos-0.002 0.10 0.022], ...
              'FontSize', 7, 'Tag', 'hlFloorTgnd');
    hlFloorTgndUnit = uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'C', ...
              'Units', 'normalized', ...
              'Position', [0.78 yPos 0.06 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    yPos = yPos - 0.028;

    % --- Section 3: Internal Heat Gains ---
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', '--- Internal Gains ---', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.022], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);
    yPos = yPos - 0.028;

    % Lighting
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'Lighting:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.18 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlLighting = uicontrol('Parent', tab4, 'Style', 'edit', ...
              'String', '500', ...
              'Units', 'normalized', ...
              'Position', [0.23 yPos-0.002 0.14 0.022], ...
              'FontSize', 7, 'Tag', 'hlLighting');
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'W  Div:', ...
              'Units', 'normalized', ...
              'Position', [0.38 yPos 0.12 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlLightingDiv = uicontrol('Parent', tab4, 'Style', 'edit', ...
              'String', '1.0', ...
              'Units', 'normalized', ...
              'Position', [0.50 yPos-0.002 0.08 0.022], ...
              'FontSize', 7, 'Tag', 'hlLightingDiv');

    % Equipment (same row, right side)
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'Equip:', ...
              'Units', 'normalized', ...
              'Position', [0.60 yPos 0.12 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlEquipment = uicontrol('Parent', tab4, 'Style', 'edit', ...
              'String', '300', ...
              'Units', 'normalized', ...
              'Position', [0.72 yPos-0.002 0.12 0.022], ...
              'FontSize', 7, 'Tag', 'hlEquipment');
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'W', ...
              'Units', 'normalized', ...
              'Position', [0.85 yPos 0.05 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlEquipDiv = uicontrol('Parent', tab4, 'Style', 'edit', ...
              'String', '1.0', ...
              'Units', 'normalized', ...
              'Position', [0.90 yPos-0.002 0.08 0.022], ...
              'FontSize', 7, 'Tag', 'hlEquipDiv', 'Visible', 'off');
    yPos = yPos - 0.027;

    % Occupants
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'Occupants:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.18 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlOccupants = uicontrol('Parent', tab4, 'Style', 'edit', ...
              'String', '5', ...
              'Units', 'normalized', ...
              'Position', [0.23 yPos-0.002 0.10 0.022], ...
              'FontSize', 7, 'Tag', 'hlOccupants');
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'Activity:', ...
              'Units', 'normalized', ...
              'Position', [0.35 yPos 0.13 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlActivity = uicontrol('Parent', tab4, 'Style', 'popupmenu', ...
              'String', {'Sedentary (75/55W)', 'Light Work (75/75W)', ...
                         'Moderate (75/170W)', 'Heavy (170/255W)'}, ...
              'Units', 'normalized', ...
              'Position', [0.48 yPos-0.003 0.50 0.025], ...
              'FontSize', 7, 'Tag', 'hlActivity');
    yPos = yPos - 0.027;

    % Moisture process load
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'Moisture Load:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.20 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlMoisture = uicontrol('Parent', tab4, 'Style', 'edit', ...
              'String', '0', ...
              'Units', 'normalized', ...
              'Position', [0.25 yPos-0.002 0.12 0.022], ...
              'FontSize', 7, 'Tag', 'hlMoisture');
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'W (latent)', ...
              'Units', 'normalized', ...
              'Position', [0.38 yPos 0.18 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    yPos = yPos - 0.028;

    % --- Section 4: Ventilation & Infiltration ---
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', '--- Ventilation & Infiltration ---', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.022], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);
    yPos = yPos - 0.027;

    % Ventilation rate
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'Ventilation:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.18 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlVentRate = uicontrol('Parent', tab4, 'Style', 'edit', ...
              'String', '50', ...
              'Units', 'normalized', ...
              'Position', [0.23 yPos-0.002 0.14 0.022], ...
              'FontSize', 7, 'Tag', 'hlVentRate');
    hlVentRateUnit = uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'L/s', ...
              'Units', 'normalized', ...
              'Position', [0.38 yPos 0.10 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlVentAutoCalc = uicontrol('Parent', tab4, 'Style', 'pushbutton', ...
              'String', 'Auto (10L/s/person)', ...
              'Units', 'normalized', ...
              'Position', [0.50 yPos-0.002 0.48 0.022], ...
              'FontSize', 6, ...
              'BackgroundColor', [0.85 0.85 0.95], ...
              'Callback', @hlVentAutoCalcCallback);
    yPos = yPos - 0.027;

    % Infiltration ACH
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'Infiltration:', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.18 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlInfiltrationACH = uicontrol('Parent', tab4, 'Style', 'edit', ...
              'String', '0.5', ...
              'Units', 'normalized', ...
              'Position', [0.23 yPos-0.002 0.14 0.022], ...
              'FontSize', 7, 'Tag', 'hlInfiltrationACH');
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'ACH', ...
              'Units', 'normalized', ...
              'Position', [0.38 yPos 0.10 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);

    % Room volume display (synced from Tab 2)
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', 'Room Vol:', ...
              'Units', 'normalized', ...
              'Position', [0.50 yPos 0.14 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    hlRoomVolDisplay = uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', '100 m^3 (from Tab 2)', ...
              'Units', 'normalized', ...
              'Position', [0.64 yPos 0.34 0.020], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, 'FontWeight', 'bold', ...
              'ForegroundColor', [0 0.3 0.6], ...
              'BackgroundColor', [0.94 0.94 0.94]);
    yPos = yPos - 0.03;

    % CALCULATE button
    uicontrol('Parent', tab4, 'Style', 'pushbutton', ...
              'String', '=== CALCULATE HEAT LOAD ===', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.030], ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.2 0.6 0.2], ...
              'ForegroundColor', [1 1 1], ...
              'Callback', @calculateHeatLoad);
    yPos = yPos - 0.035;

    % --- Section 5: Results (scrollable table) ---
    uicontrol('Parent', tab4, 'Style', 'text', ...
              'String', '--- Heat Load Results ---', ...
              'Units', 'normalized', ...
              'Position', [0.05 yPos 0.90 0.022], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);
    yPos = yPos - 0.025;

    % Results as scrollable uitable
    hlResultRowNames = {'Envelope (walls+roof)'; 'Floor'; 'Glass (cond+solar)'; ...
                        'Internal Sensible'; 'Internal Latent'; ...
                        'Ventilation (S+L)'; 'Infiltration (S+L)'; ...
                        '--------------------'; ...
                        'TOTAL SENSIBLE'; 'TOTAL LATENT'; ...
                        'TOTAL LOAD'; 'SHR'};
    hlResultDefaultData = {'---'; '---'; '---'; '---'; '---'; '---'; '---'; ...
                           ''; '---'; '---'; '---'; '---'};

    hlResultsTable = uitable('Parent', tab4, ...
              'Units', 'normalized', ...
              'Position', [0.02 0.04 0.96 yPos+0.005], ...
              'Data', hlResultDefaultData, ...
              'ColumnName', {'Value'}, ...
              'RowName', hlResultRowNames, ...
              'ColumnEditable', false, ...
              'ColumnWidth', {120}, ...
              'FontSize', 8, ...
              'Tag', 'hlResultsTable');

    % Keep hlResults as a struct with field names for backward compat
    hlResults = struct();
    hlResults.tableHandle = hlResultsTable;
    hlResults.rowMap = struct('hlWalls', 1, 'hlFloor', 2, 'hlGlassCond', 3, ...
                              'hlIntSens', 4, 'hlIntLat', 5, ...
                              'hlVentSens', 6, 'hlInfSens', 7, ...
                              'hlTotSens', 9, 'hlTotLat', 10, ...
                              'hlTotLoad', 11, 'hlSHR', 12);
    hlResultsPanel = hlResultsTable;  % alias for handle storage

    % Send to Process Analysis button (at very bottom of tab)
    hlSendToProcess = uicontrol('Parent', tab4, 'Style', 'pushbutton', ...
              'String', 'Send to Process Analysis -->', ...
              'Units', 'normalized', ...
              'Position', [0.10 0.008 0.80 0.028], ...
              'FontSize', 8, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.3 0.5 0.8], ...
              'ForegroundColor', [1 1 1], ...
              'Callback', @hlSendToProcessCallback);

    %% ===== TAB 5: Live Sensor =====

    % --- Connection Panel ---
    lsConnPanel = uipanel('Parent', tab5, ...
                          'Title', 'Connection', ...
                          'FontSize', 10, 'FontWeight', 'bold', ...
                          'Units', 'normalized', ...
                          'Position', [0.02 0.82 0.96 0.17], ...
                          'BackgroundColor', [0.94 0.94 0.94]);

    uicontrol('Parent', lsConnPanel, 'Style', 'text', ...
              'String', 'Port:', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.65 0.10 0.25], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 10, ...
              'BackgroundColor', [0.94 0.94 0.94]);

    lsPortInput = uicontrol('Parent', lsConnPanel, 'Style', 'edit', ...
              'String', '', ...  % filled by the Detect button
              'Units', 'normalized', ...
              'Position', [0.12 0.65 0.45 0.28], ...
              'FontSize', 9, ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', lsConnPanel, 'Style', 'pushbutton', ...
              'String', 'Detect', ...
              'Units', 'normalized', ...
              'Position', [0.58 0.65 0.15 0.28], ...
              'FontSize', 9, ...
              'Callback', @lsDetectPortCallback);

    uicontrol('Parent', lsConnPanel, 'Style', 'text', ...
              'String', 'Board:', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.30 0.10 0.25], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 10, ...
              'BackgroundColor', [0.94 0.94 0.94]);

    lsBoardDropdown = uicontrol('Parent', lsConnPanel, 'Style', 'popupmenu', ...
              'String', {'Uno', 'Mega2560', 'Nano'}, ...
              'Units', 'normalized', ...
              'Position', [0.12 0.30 0.30 0.28], ...
              'FontSize', 9);

    lsConnectBtn = uicontrol('Parent', lsConnPanel, 'Style', 'togglebutton', ...
              'String', 'Connect', ...
              'Units', 'normalized', ...
              'Position', [0.75 0.35 0.22 0.55], ...
              'FontSize', 10, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.3 0.7 0.3], ...
              'ForegroundColor', [1 1 1], ...
              'Callback', @lsConnectCallback);

    lsStatusText = uicontrol('Parent', lsConnPanel, 'Style', 'text', ...
              'String', 'Disconnected', ...
              'Units', 'normalized', ...
              'Position', [0.45 0.02 0.52 0.25], ...
              'HorizontalAlignment', 'right', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'ForegroundColor', [0.8 0.1 0.1], ...
              'BackgroundColor', [0.94 0.94 0.94]);

    % --- Live Readings Panel ---
    lsReadPanel = uipanel('Parent', tab5, ...
                          'Title', 'Live Readings', ...
                          'FontSize', 10, 'FontWeight', 'bold', ...
                          'Units', 'normalized', ...
                          'Position', [0.02 0.38 0.96 0.43], ...
                          'BackgroundColor', [0.94 0.94 0.94]);

    % Temperature
    uicontrol('Parent', lsReadPanel, 'Style', 'text', ...
              'String', 'Temperature:', ...
              'Units', 'normalized', ...
              'Position', [0.03 0.88 0.35 0.08], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 10, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);
    lsTempDisplay = uicontrol('Parent', lsReadPanel, 'Style', 'text', ...
              'String', '--- degC', ...
              'Units', 'normalized', ...
              'Position', [0.40 0.86 0.55 0.12], ...
              'HorizontalAlignment', 'right', ...
              'FontSize', 14, 'FontWeight', 'bold', ...
              'ForegroundColor', [0.1 0.3 0.7], ...
              'BackgroundColor', [0.94 0.94 0.94]);

    % Relative Humidity
    uicontrol('Parent', lsReadPanel, 'Style', 'text', ...
              'String', 'Relative Humidity:', ...
              'Units', 'normalized', ...
              'Position', [0.03 0.76 0.35 0.08], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 10, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);
    lsRHDisplay = uicontrol('Parent', lsReadPanel, 'Style', 'text', ...
              'String', '--- %', ...
              'Units', 'normalized', ...
              'Position', [0.40 0.74 0.55 0.12], ...
              'HorizontalAlignment', 'right', ...
              'FontSize', 14, 'FontWeight', 'bold', ...
              'ForegroundColor', [0.1 0.3 0.7], ...
              'BackgroundColor', [0.94 0.94 0.94]);

    % Pressure
    uicontrol('Parent', lsReadPanel, 'Style', 'text', ...
              'String', 'Pressure:', ...
              'Units', 'normalized', ...
              'Position', [0.03 0.64 0.35 0.08], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 10, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    lsPressDisplay = uicontrol('Parent', lsReadPanel, 'Style', 'text', ...
              'String', '--- Pa', ...
              'Units', 'normalized', ...
              'Position', [0.40 0.64 0.55 0.08], ...
              'HorizontalAlignment', 'right', ...
              'FontSize', 10, ...
              'ForegroundColor', [0.3 0.3 0.3], ...
              'BackgroundColor', [0.94 0.94 0.94]);

    % Humidity Ratio
    uicontrol('Parent', lsReadPanel, 'Style', 'text', ...
              'String', 'Humidity Ratio (W):', ...
              'Units', 'normalized', ...
              'Position', [0.03 0.54 0.35 0.08], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 10, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    lsWDisplay = uicontrol('Parent', lsReadPanel, 'Style', 'text', ...
              'String', '--- kg/kg', ...
              'Units', 'normalized', ...
              'Position', [0.40 0.54 0.55 0.08], ...
              'HorizontalAlignment', 'right', ...
              'FontSize', 10, ...
              'ForegroundColor', [0.3 0.3 0.3], ...
              'BackgroundColor', [0.94 0.94 0.94]);

    % Wet-Bulb Temperature
    uicontrol('Parent', lsReadPanel, 'Style', 'text', ...
              'String', 'Wet-Bulb Temp:', ...
              'Units', 'normalized', ...
              'Position', [0.03 0.44 0.35 0.08], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 10, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    lsTwbDisplay = uicontrol('Parent', lsReadPanel, 'Style', 'text', ...
              'String', '--- degC', ...
              'Units', 'normalized', ...
              'Position', [0.40 0.44 0.55 0.08], ...
              'HorizontalAlignment', 'right', ...
              'FontSize', 10, ...
              'ForegroundColor', [0.3 0.3 0.3], ...
              'BackgroundColor', [0.94 0.94 0.94]);

    % Dew Point Temperature
    uicontrol('Parent', lsReadPanel, 'Style', 'text', ...
              'String', 'Dew Point Temp:', ...
              'Units', 'normalized', ...
              'Position', [0.03 0.34 0.35 0.08], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 10, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    lsTdpDisplay = uicontrol('Parent', lsReadPanel, 'Style', 'text', ...
              'String', '--- degC', ...
              'Units', 'normalized', ...
              'Position', [0.40 0.34 0.55 0.08], ...
              'HorizontalAlignment', 'right', ...
              'FontSize', 10, ...
              'ForegroundColor', [0.3 0.3 0.3], ...
              'BackgroundColor', [0.94 0.94 0.94]);

    % Specific Enthalpy
    uicontrol('Parent', lsReadPanel, 'Style', 'text', ...
              'String', 'Enthalpy:', ...
              'Units', 'normalized', ...
              'Position', [0.03 0.24 0.35 0.08], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 10, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    lsEnthalpyDisplay = uicontrol('Parent', lsReadPanel, 'Style', 'text', ...
              'String', '--- kJ/kg', ...
              'Units', 'normalized', ...
              'Position', [0.40 0.24 0.55 0.08], ...
              'HorizontalAlignment', 'right', ...
              'FontSize', 10, ...
              'ForegroundColor', [0.3 0.3 0.3], ...
              'BackgroundColor', [0.94 0.94 0.94]);

    % Specific Volume
    uicontrol('Parent', lsReadPanel, 'Style', 'text', ...
              'String', 'Specific Volume:', ...
              'Units', 'normalized', ...
              'Position', [0.03 0.14 0.35 0.08], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 10, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    lsVolumeDisplay = uicontrol('Parent', lsReadPanel, 'Style', 'text', ...
              'String', '--- m3/kg', ...
              'Units', 'normalized', ...
              'Position', [0.40 0.14 0.55 0.08], ...
              'HorizontalAlignment', 'right', ...
              'FontSize', 10, ...
              'ForegroundColor', [0.3 0.3 0.3], ...
              'BackgroundColor', [0.94 0.94 0.94]);

    % Update interval
    uicontrol('Parent', lsReadPanel, 'Style', 'text', ...
              'String', 'Update Interval:', ...
              'Units', 'normalized', ...
              'Position', [0.03 0.02 0.30 0.08], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 10, ...
              'BackgroundColor', [0.94 0.94 0.94]);
    lsIntervalDropdown = uicontrol('Parent', lsReadPanel, 'Style', 'popupmenu', ...
              'String', {'1s', '2s', '5s', '10s'}, ...
              'Value', 2, ...
              'Units', 'normalized', ...
              'Position', [0.35 0.02 0.20 0.09], ...
              'FontSize', 9, ...
              'Callback', @lsIntervalCallback);

    % --- Comfort Assessment Panel (standalone) ---
    lsComfortPanel = uipanel('Parent', tab5, ...
                             'Title', 'Comfort Assessment (ASHRAE 55)', ...
                             'FontSize', 10, 'FontWeight', 'bold', ...
                             'Units', 'normalized', ...
                             'Position', [0.02 0.29 0.96 0.08], ...
                             'BackgroundColor', [0.94 0.94 0.94]);
    lsComfortText = uicontrol('Parent', lsComfortPanel, 'Style', 'text', ...
              'String', '---', ...
              'Units', 'normalized', ...
              'Position', [0.05 0.05 0.90 0.85], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 11, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.94 0.94 0.94]);

    % --- Controls Panel ---
    lsCtrlPanel = uipanel('Parent', tab5, ...
                          'Title', 'Controls', ...
                          'FontSize', 10, 'FontWeight', 'bold', ...
                          'Units', 'normalized', ...
                          'Position', [0.02 0.02 0.96 0.26], ...
                          'BackgroundColor', [0.94 0.94 0.94]);

    lsPlotOnChart = uicontrol('Parent', lsCtrlPanel, 'Style', 'checkbox', ...
              'String', 'Plot on Chart', ...
              'Value', 1, ...
              'Units', 'normalized', ...
              'Position', [0.05 0.75 0.40 0.18], ...
              'FontSize', 10, ...
              'BackgroundColor', [0.94 0.94 0.94]);

    lsLogBtn = uicontrol('Parent', lsCtrlPanel, 'Style', 'togglebutton', ...
              'String', 'Log Data', ...
              'Units', 'normalized', ...
              'Position', [0.05 0.42 0.28 0.25], ...
              'FontSize', 10, ...
              'BackgroundColor', [0.85 0.85 0.85], ...
              'Callback', @lsLogCallback);

    uicontrol('Parent', lsCtrlPanel, 'Style', 'pushbutton', ...
              'String', 'Export CSV', ...
              'Units', 'normalized', ...
              'Position', [0.36 0.42 0.28 0.25], ...
              'FontSize', 10, ...
              'BackgroundColor', [0.3 0.5 0.8], ...
              'ForegroundColor', [1 1 1], ...
              'Callback', @lsExportCallback);

    uicontrol('Parent', lsCtrlPanel, 'Style', 'pushbutton', ...
              'String', 'Clear Log', ...
              'Units', 'normalized', ...
              'Position', [0.67 0.42 0.28 0.25], ...
              'FontSize', 10, ...
              'BackgroundColor', [0.8 0.3 0.3], ...
              'ForegroundColor', [1 1 1], ...
              'Callback', @lsClearLogCallback);

    lsLogCount = uicontrol('Parent', lsCtrlPanel, 'Style', 'text', ...
              'String', 'Logged points: 0', ...
              'Units', 'normalized', ...
              'Position', [0.05 0.10 0.90 0.22], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 10, ...
              'BackgroundColor', [0.94 0.94 0.94]);

    %% ===== Status bar (outside tabs) =====
    statusText = uicontrol('Parent', controlPanel, 'Style', 'text', ...
              'String', 'Ready. Click on the chart to analyse a point.', ...
              'Units', 'normalized', ...
              'Position', [0.03 0.01 0.94 0.03], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 8, ...
              'ForegroundColor', [0.3 0.3 0.3], ...
              'BackgroundColor', [0.90 0.90 0.90]);

    %% Store handles in figure
    handles = struct();
    handles.ax = ax;
    handles.fig = fig;
    handles.propHandles = propHandles;
    handles.procHandles = procHandles;
    handles.firstPropDropdown = firstPropDropdown;
    handles.firstPropInput = firstPropInput;
    handles.firstPropUnit = firstPropUnit;
    handles.secondPropDropdown = secondPropDropdown;
    handles.secondPropInput = secondPropInput;
    handles.secondPropUnit = secondPropUnit;
    handles.pointADropdown = pointADropdown;
    handles.pointBDropdown = pointBDropdown;
    handles.flowRateInput = flowRateInput;
    handles.flowRateUnit = flowRateUnit;
    handles.roomVolumeInput = roomVolumeInput;
    handles.roomVolumeUnit = roomVolumeUnit;
    handles.achInput = achInput;
    handles.bypassFactorInput = bypassFactorInput;
    handles.volFlowDisplay = volFlowDisplay;
    handles.massFlowDisplay = massFlowDisplay;
    handles.statusText = statusText;
    handles.chartPanel = chartPanel;
    handles.tabGroup = tabGroup;
    handles.comfortZoneCheckbox = comfortZoneCheckbox;
    handles.comfortPointDropdown = comfortPointDropdown;
    handles.cloSlider = cloSlider;
    handles.cloInput = cloInput;
    handles.cloDescription = cloDescription;
    handles.metSlider = metSlider;
    handles.metInput = metInput;
    handles.metPresetDropdown = metPresetDropdown;
    handles.airVelSlider = airVelSlider;
    handles.airVelInput = airVelInput;
    handles.airVelUnit = airVelUnit;
    handles.comfortResults = comfortResults;
    handles.currentPoint = [];
    handles.markerHandles = [];
    handles.currentMarkerHandle = [];

    % Tab 4: Heat Load handles
    handles.hlLoadType = hlLoadType;
    handles.hlOutdoorTemp = hlOutdoorTemp;
    handles.hlOutdoorTempUnit = hlOutdoorTempUnit;
    handles.hlOutdoorRH = hlOutdoorRH;
    handles.hlIndoorTemp = hlIndoorTemp;
    handles.hlIndoorTempUnit = hlIndoorTempUnit;
    handles.hlIndoorRH = hlIndoorRH;
    handles.hlCLTDAutoCorrect = hlCLTDAutoCorrect;
    handles.hlEnvelopeTable = hlEnvelopeTable;
    handles.hlEnvUnitLabel = hlEnvUnitLabel;
    handles.hlIncludeFloor = hlIncludeFloor;
    handles.hlFloorU = hlFloorU;
    handles.hlFloorArea = hlFloorArea;
    handles.hlFloorTgnd = hlFloorTgnd;
    handles.hlFloorTgndUnit = hlFloorTgndUnit;
    handles.hlLighting = hlLighting;
    handles.hlLightingDiv = hlLightingDiv;
    handles.hlEquipment = hlEquipment;
    handles.hlEquipDiv = hlEquipDiv;
    handles.hlOccupants = hlOccupants;
    handles.hlActivity = hlActivity;
    handles.hlMoisture = hlMoisture;
    handles.hlVentRate = hlVentRate;
    handles.hlVentRateUnit = hlVentRateUnit;
    handles.hlInfiltrationACH = hlInfiltrationACH;
    handles.hlRoomVolDisplay = hlRoomVolDisplay;
    handles.hlResults = hlResults;
    handles.hlResultsPanel = hlResultsPanel;
    handles.hlOutdoorSource = hlOutdoorSource;
    handles.hlIndoorSource = hlIndoorSource;

    % Tab 5: Live Sensor handles
    handles.lsPortInput = lsPortInput;
    handles.lsBoardDropdown = lsBoardDropdown;
    handles.lsConnectBtn = lsConnectBtn;
    handles.lsStatusText = lsStatusText;
    handles.lsArduino = [];
    handles.lsSensor = [];
    handles.lsTempDisplay = lsTempDisplay;
    handles.lsRHDisplay = lsRHDisplay;
    handles.lsPressDisplay = lsPressDisplay;
    handles.lsWDisplay = lsWDisplay;
    handles.lsTwbDisplay = lsTwbDisplay;
    handles.lsTdpDisplay = lsTdpDisplay;
    handles.lsEnthalpyDisplay = lsEnthalpyDisplay;
    handles.lsVolumeDisplay = lsVolumeDisplay;
    handles.lsComfortText = lsComfortText;
    handles.lsPlotOnChart = lsPlotOnChart;
    handles.lsLogBtn = lsLogBtn;
    handles.lsLogCount = lsLogCount;
    handles.lsTimer = [];
    handles.lsSensorMarker = [];
    handles.lsSensorLabel = [];
    handles.lsLogData = {};
    handles.lsIntervalDropdown = lsIntervalDropdown;

    guidata(fig, handles);
    setappdata(fig, 'appData', appData);

    %% Draw initial chart
    drawChart(fig);
    updateComfortAssessment();

    %% Set up click callback
    set(ax, 'ButtonDownFcn', @chartClick);

    %% ==================== CALLBACK FUNCTIONS ====================

    function unitChanged(~, event)
        handles = guidata(fig);
        appData = getappdata(fig, 'appData');

        if strcmp(event.NewValue.Tag, 'SI')
            appData.unitSystem = 2;
            appData.pressure = 101325;
            appData.TRange = [0 50];
        else
            appData.unitSystem = 1;
            appData.pressure = 14.696;
            appData.TRange = [0 120];
        end

        setappdata(fig, 'appData', appData);
        updateInputLabels();
        updateFlowRateUnit();
        updateAirVelUnit();
        updateHeatLoadUnits();
        clearMarks([], []);
        drawChart(fig);
        resetProperties();
        resetProcessResults();
        updateComfortAssessment();
        updateStatus('Unit system changed. Chart redrawn.');
    end

    function toggleComfortZone(src, ~)
        appData = getappdata(fig, 'appData');
        appData.showComfortZone = logical(get(src, 'Value'));
        setappdata(fig, 'appData', appData);
        drawChart(fig);
        updateComfortAssessment();
        if appData.showComfortZone
            updateStatus('ASHRAE 55 comfort zone shown.');
        else
            updateStatus('ASHRAE 55 comfort zone hidden.');
        end
    end

    function comfortPointChanged(src, ~)
        handles = guidata(fig);
        appData = getappdata(fig, 'appData');
        idx = get(src, 'Value');
        if idx == 1
            % "Current click" selected
            appData.comfortLockedPoint = 0;
            updateStatus('Comfort assessment follows current click.');
        else
            % Locked to a marked point (idx-1 because first entry is "Current click")
            pointIdx = idx - 1;
            appData.comfortLockedPoint = pointIdx;
            updateStatus(sprintf('Comfort assessment locked to P%d.', pointIdx));
        end
        setappdata(fig, 'appData', appData);
        updateComfortAssessment();
    end

    function cloSliderChanged(src, ~)
        val = round(get(src, 'Value') * 10) / 10;  % snap to 0.1
        set(src, 'Value', val);
        handles = guidata(fig);
        set(handles.cloInput, 'String', sprintf('%.1f', val));
        appData = getappdata(fig, 'appData');
        appData.comfortClo = val;
        setappdata(fig, 'appData', appData);
        updateCloDescription(val);
        drawChart(fig);
        updateComfortAssessment();
        updateStatus(sprintf('Clothing insulation: %.1f clo', val));
    end

    function cloInputChanged(src, ~)
        val = str2double(get(src, 'String'));
        if isnan(val) || val < 0.3 || val > 1.5
            updateStatus('Clo value must be between 0.3 and 1.5.');
            appData = getappdata(fig, 'appData');
            set(src, 'String', sprintf('%.1f', appData.comfortClo));
            return;
        end
        val = round(val * 10) / 10;
        handles = guidata(fig);
        set(handles.cloSlider, 'Value', val);
        set(src, 'String', sprintf('%.1f', val));
        appData = getappdata(fig, 'appData');
        appData.comfortClo = val;
        setappdata(fig, 'appData', appData);
        updateCloDescription(val);
        drawChart(fig);
        updateComfortAssessment();
        updateStatus(sprintf('Clothing insulation: %.1f clo', val));
    end

    function cloPreset(~, ~, val)
        handles = guidata(fig);
        set(handles.cloSlider, 'Value', val);
        set(handles.cloInput, 'String', sprintf('%.1f', val));
        appData = getappdata(fig, 'appData');
        appData.comfortClo = val;
        setappdata(fig, 'appData', appData);
        updateCloDescription(val);
        drawChart(fig);
        updateComfortAssessment();
        updateStatus(sprintf('Clothing preset: %.1f clo', val));
    end

    function metSliderChanged(src, ~)
        val = round(get(src, 'Value') * 10) / 10;
        set(src, 'Value', val);
        handles = guidata(fig);
        set(handles.metInput, 'String', sprintf('%.1f', val));
        appData = getappdata(fig, 'appData');
        appData.comfortMet = val;
        setappdata(fig, 'appData', appData);
        updateMetDropdown(val);
        drawChart(fig);
        updateComfortAssessment();
        updateStatus(sprintf('Metabolic rate: %.1f met', val));
    end

    function metInputChanged(src, ~)
        val = str2double(get(src, 'String'));
        if isnan(val) || val < 1.0 || val > 2.0
            updateStatus('Met value must be between 1.0 and 2.0.');
            appData = getappdata(fig, 'appData');
            set(src, 'String', sprintf('%.1f', appData.comfortMet));
            return;
        end
        val = round(val * 10) / 10;
        handles = guidata(fig);
        set(handles.metSlider, 'Value', val);
        set(src, 'String', sprintf('%.1f', val));
        appData = getappdata(fig, 'appData');
        appData.comfortMet = val;
        setappdata(fig, 'appData', appData);
        updateMetDropdown(val);
        drawChart(fig);
        updateComfortAssessment();
        updateStatus(sprintf('Metabolic rate: %.1f met', val));
    end

    function metPresetChanged(src, ~)
        metValues = [1.0, 1.1, 1.2, 1.3, 1.6, 2.0];
        idx = get(src, 'Value');
        val = metValues(idx);
        handles = guidata(fig);
        set(handles.metSlider, 'Value', val);
        set(handles.metInput, 'String', sprintf('%.1f', val));
        appData = getappdata(fig, 'appData');
        appData.comfortMet = val;
        setappdata(fig, 'appData', appData);
        drawChart(fig);
        updateComfortAssessment();
        updateStatus(sprintf('Metabolic rate: %.1f met', val));
    end

    function airVelSliderChanged(src, ~)
        val = round(get(src, 'Value') * 10) / 10;
        set(src, 'Value', val);
        handles = guidata(fig);
        set(handles.airVelInput, 'String', sprintf('%.1f', val));
        appData = getappdata(fig, 'appData');
        appData.comfortAirVel = val;
        setappdata(fig, 'appData', appData);
        drawChart(fig);
        updateComfortAssessment();
        updateStatus(sprintf('Air velocity: %.1f m/s', val));
    end

    function airVelInputChanged(src, ~)
        val = str2double(get(src, 'String'));
        if isnan(val) || val < 0.1 || val > 1.2
            updateStatus('Air velocity must be between 0.1 and 1.2 m/s.');
            appData = getappdata(fig, 'appData');
            set(src, 'String', sprintf('%.1f', appData.comfortAirVel));
            return;
        end
        val = round(val * 10) / 10;
        handles = guidata(fig);
        set(handles.airVelSlider, 'Value', val);
        set(src, 'String', sprintf('%.1f', val));
        appData = getappdata(fig, 'appData');
        appData.comfortAirVel = val;
        setappdata(fig, 'appData', appData);
        drawChart(fig);
        updateComfortAssessment();
        updateStatus(sprintf('Air velocity: %.1f m/s', val));
    end

    function updateCloDescription(cloVal)
        handles = guidata(fig);
        desc = psychro.getClothingDescription(cloVal);
        set(handles.cloDescription, 'String', desc);
    end

    function updateMetDropdown(metVal)
        handles = guidata(fig);
        metValues = [1.0, 1.1, 1.2, 1.3, 1.6, 2.0];
        [~, idx] = min(abs(metValues - metVal));
        if abs(metValues(idx) - metVal) < 0.05
            set(handles.metPresetDropdown, 'Value', idx);
        end
    end

    function updateComfortAssessment()
        handles = guidata(fig);
        appData = getappdata(fig, 'appData');

        % Get comfort zone boundaries
        [T_lo, T_hi] = psychro.getComfortTempRange(appData.comfortClo, ...
            appData.comfortMet, appData.comfortAirVel, appData.unitSystem);

        if appData.unitSystem == 2
            set(handles.comfortResults.czRange, 'String', ...
                sprintf('%.1f - %.1f C', T_lo, T_hi));
        else
            set(handles.comfortResults.czRange, 'String', ...
                sprintf('%.1f - %.1f F', T_lo, T_hi));
        end

        % Determine which point to assess
        assessPoint = [];
        if appData.comfortLockedPoint > 0 && ~isempty(appData.markedPoints) ...
                && appData.comfortLockedPoint <= length(appData.markedPoints)
            % Locked to a marked point
            assessPoint = appData.markedPoints(appData.comfortLockedPoint);
        elseif ~isempty(handles.currentPoint)
            % Follow current click
            assessPoint = handles.currentPoint;
        end

        % Assess the point
        if ~isempty(assessPoint)
            T = assessPoint.T;
            W = assessPoint.W;
            RH = assessPoint.RH;

            % Operative temp (assume MRT = air temp for this tool)
            To = T;
            if appData.unitSystem == 2
                set(handles.comfortResults.czTo, 'String', sprintf('%.2f C', To));
            else
                set(handles.comfortResults.czTo, 'String', sprintf('%.2f F', To));
            end

            % Check if point is within comfort zone
            W_limit = 0.012;
            inZone = (To >= T_lo) && (To <= T_hi) && (W <= W_limit);

            if inZone
                set(handles.comfortResults.czStatus, 'String', 'Within Comfort Zone');
                set(handles.comfortResults.czStatus, 'ForegroundColor', [0 0.6 0]);
            else
                reasons = {};
                if To < T_lo
                    reasons{end+1} = 'Too cool';
                elseif To > T_hi
                    reasons{end+1} = 'Too warm';
                end
                if W > W_limit
                    reasons{end+1} = 'Too humid';
                end
                statusStr = ['Outside - ' strjoin(reasons, ', ')];
                set(handles.comfortResults.czStatus, 'String', statusStr);
                set(handles.comfortResults.czStatus, 'ForegroundColor', [0.8 0 0]);
            end

            % PMV estimate (simplified Fanger model)
            pmv = psychro.estimatePMV(To, RH, appData.comfortClo, ...
                              appData.comfortMet, appData.comfortAirVel, appData.unitSystem);
            ppd = 100 - 95 * exp(-0.03353 * pmv^4 - 0.2179 * pmv^2);
            ppd = max(5, min(100, ppd));

            set(handles.comfortResults.czPMV, 'String', sprintf('%.2f', pmv));
            set(handles.comfortResults.czPPD, 'String', sprintf('%.1f %%', ppd));

            % Colour the PMV value
            if abs(pmv) <= 0.5
                set(handles.comfortResults.czPMV, 'ForegroundColor', [0 0.6 0]);
            elseif abs(pmv) <= 1.0
                set(handles.comfortResults.czPMV, 'ForegroundColor', [0.8 0.5 0]);
            else
                set(handles.comfortResults.czPMV, 'ForegroundColor', [0.8 0 0]);
            end
        else
            set(handles.comfortResults.czStatus, 'String', 'No point selected');
            set(handles.comfortResults.czStatus, 'ForegroundColor', [0.4 0.4 0.4]);
            set(handles.comfortResults.czTo, 'String', '---');
            set(handles.comfortResults.czPMV, 'String', '---');
            set(handles.comfortResults.czPPD, 'String', '---');
        end
    end

    function propDropdownChanged(src, ~)
        handles = guidata(fig);

        prop1 = get(handles.firstPropDropdown, 'Value');
        prop2 = get(handles.secondPropDropdown, 'Value');

        if prop1 == prop2
            if strcmp(src.Tag, 'firstPropDropdown')
                newVal = mod(prop2, 6) + 1;
                set(handles.secondPropDropdown, 'Value', newVal);
            else
                newVal = mod(prop1, 6) + 1;
                set(handles.firstPropDropdown, 'Value', newVal);
            end
        end

        updateDropdownUnits();
        updateStatus('Input properties changed. Enter values and click Calculate.');
    end

    function updateDropdownUnits()
        handles = guidata(fig);
        appData = getappdata(fig, 'appData');
        isSI = (appData.unitSystem == 2);

        prop1 = get(handles.firstPropDropdown, 'Value');
        prop2 = get(handles.secondPropDropdown, 'Value');

        set(handles.firstPropUnit, 'String', getUnitForProperty(prop1, isSI));
        set(handles.firstPropInput, 'String', getDefaultForProperty(prop1, isSI));
        set(handles.secondPropUnit, 'String', getUnitForProperty(prop2, isSI));
        set(handles.secondPropInput, 'String', getDefaultForProperty(prop2, isSI));
    end

    function unit = getUnitForProperty(propIdx, isSI)
        switch propIdx
            case {1, 2, 3}
                if isSI, unit = 'C'; else, unit = 'F'; end
            case 4
                if isSI, unit = 'kg/kg'; else, unit = 'lb/lb'; end
            case 5
                if isSI, unit = 'kJ/kg'; else, unit = 'Btu/lb'; end
            case 6
                unit = '%';
            otherwise
                unit = '';
        end
    end

    function val = getDefaultForProperty(propIdx, isSI)
        switch propIdx
            case 1
                if isSI, val = '25'; else, val = '77'; end
            case 2
                if isSI, val = '18'; else, val = '65'; end
            case 3
                if isSI, val = '15'; else, val = '60'; end
            case 4
                val = '0.010';
            case 5
                if isSI, val = '50'; else, val = '25'; end
            case 6
                val = '50';
            otherwise
                val = '0';
        end
    end

    function updateInputLabels()
        updateDropdownUnits();
    end

    function updateFlowRateUnit()
        handles = guidata(fig);
        appData = getappdata(fig, 'appData');
        if appData.unitSystem == 2
            set(handles.flowRateUnit, 'String', 'kg/s');
            set(handles.roomVolumeUnit, 'String', 'm^3');
        else
            set(handles.flowRateUnit, 'String', 'lb/min');
            set(handles.roomVolumeUnit, 'String', 'ft^3');
        end
        % Reset computed flow displays
        set(handles.volFlowDisplay, 'String', '---');
        set(handles.massFlowDisplay, 'String', '---');
    end

    function updateAirVelUnit()
        handles = guidata(fig);
        appData = getappdata(fig, 'appData');
        if appData.unitSystem == 2
            set(handles.airVelUnit, 'String', 'm/s');
            % Convert current value from fpm to m/s if switching
        else
            set(handles.airVelUnit, 'String', 'fpm');
            % Display in fpm for IP mode
        end
    end

    %% ===== TAB 4: Heat Load Callbacks =====

    function hlSourceChangedCallback(src, ~)
        handles = guidata(fig);
        appData = getappdata(fig, 'appData');
        items = get(src, 'String');
        val = get(src, 'Value');
        selectedItem = items{val};
        isOutdoor = (src == handles.hlOutdoorSource);

        if strcmp(selectedItem, 'Manual Input')
            % Enable edit fields for manual entry
            if isOutdoor
                set(handles.hlOutdoorTemp, 'Enable', 'on');
                set(handles.hlOutdoorRH, 'Enable', 'on');
            else
                set(handles.hlIndoorTemp, 'Enable', 'on');
                set(handles.hlIndoorRH, 'Enable', 'on');
            end
            return;
        end

        % Disable edit fields when using a source
        if isOutdoor
            set(handles.hlOutdoorTemp, 'Enable', 'inactive');
            set(handles.hlOutdoorRH, 'Enable', 'inactive');
        else
            set(handles.hlIndoorTemp, 'Enable', 'inactive');
            set(handles.hlIndoorRH, 'Enable', 'inactive');
        end

        if strcmp(selectedItem, 'Live Sensor Data')
            % Will be updated by the timer callback
            liveData = getappdata(fig, 'lsLiveData');
            if ~isempty(liveData)
                if isOutdoor
                    set(handles.hlOutdoorTemp, 'String', sprintf('%.1f', liveData.T));
                    Pws_l = psychro.saturationPressure(liveData.T, appData.unitSystem);
                    Pw_l = liveData.W * appData.pressure / (0.62198 + liveData.W);
                    RH_l = (Pw_l / Pws_l) * 100;
                    set(handles.hlOutdoorRH, 'String', sprintf('%.1f', RH_l));
                else
                    set(handles.hlIndoorTemp, 'String', sprintf('%.1f', liveData.T));
                    Pws_l = psychro.saturationPressure(liveData.T, appData.unitSystem);
                    Pw_l = liveData.W * appData.pressure / (0.62198 + liveData.W);
                    RH_l = (Pw_l / Pws_l) * 100;
                    set(handles.hlIndoorRH, 'String', sprintf('%.1f', RH_l));
                end
            end
            updateStatus(sprintf('%s conditions set to Live Sensor Data.', ...
                ternary(isOutdoor, 'Outdoor', 'Indoor')));
            return;
        end

        % Must be a marked point (e.g. "P1 (T=35.0 C, W=0.01234)")
        % Extract point index from the string
        ptIdx = sscanf(selectedItem, 'P%d');
        if ~isempty(ptIdx) && ptIdx <= appData.pointCount
            pt = appData.markedPoints(ptIdx);
            if isOutdoor
                set(handles.hlOutdoorTemp, 'String', sprintf('%.1f', pt.T));
                set(handles.hlOutdoorRH, 'String', sprintf('%.0f', pt.RH * 100));
                updateStatus(sprintf('Outdoor conditions set from P%d (T=%.1f, RH=%.0f%%)', ptIdx, pt.T, pt.RH*100));
            else
                set(handles.hlIndoorTemp, 'String', sprintf('%.1f', pt.T));
                set(handles.hlIndoorRH, 'String', sprintf('%.0f', pt.RH * 100));
                updateStatus(sprintf('Indoor conditions set from P%d (T=%.1f, RH=%.0f%%)', ptIdx, pt.T, pt.RH*100));
            end
        end
    end

    function hlVentAutoCalcCallback(~, ~)
        handles = guidata(fig);
        appData = getappdata(fig, 'appData');
        nOcc = str2double(get(handles.hlOccupants, 'String'));
        if isnan(nOcc) || nOcc < 0, nOcc = 0; end
        if appData.unitSystem == 2
            ventRate = nOcc * 10;  % 10 L/s per person (ASHRAE 62.1)
        else
            ventRate = nOcc * 20;  % ~20 CFM per person
        end
        set(handles.hlVentRate, 'String', sprintf('%.0f', ventRate));
        updateStatus(sprintf('Ventilation auto-calculated: %d occupants x %.0f %s/person', ...
            round(nOcc), ternary(appData.unitSystem == 2, 10, 20), ...
            ternary(appData.unitSystem == 2, 'L/s', 'CFM')));
    end

    function calculateHeatLoad(~, ~)
        handles = guidata(fig);
        appData = getappdata(fig, 'appData');
        unitSys = appData.unitSystem;
        P = appData.pressure;

        try
            % === Read design conditions ===
            T_out = str2double(get(handles.hlOutdoorTemp, 'String'));
            RH_out = str2double(get(handles.hlOutdoorRH, 'String'));
            T_in = str2double(get(handles.hlIndoorTemp, 'String'));
            RH_in = str2double(get(handles.hlIndoorRH, 'String'));
            loadType = get(handles.hlLoadType, 'Value');  % 1=Cooling, 2=Heating

            if any(isnan([T_out RH_out T_in RH_in]))
                updateStatus('Invalid design conditions. Check temperature and RH inputs.');
                return;
            end

            % Compute humidity ratios from design conditions
            Pws_out = psychro.saturationPressure(T_out, unitSys);
            Pw_out = (RH_out / 100) * Pws_out;
            W_out = psychro.humidityRatio(Pw_out, P, unitSys);

            Pws_in = psychro.saturationPressure(T_in, unitSys);
            Pw_in = (RH_in / 100) * Pws_in;
            W_in = psychro.humidityRatio(Pw_in, P, unitSys);

            dT = T_out - T_in;
            dW = W_out - W_in;

            % CLTD auto-correction
            autoCorrectCLTD = get(handles.hlCLTDAutoCorrect, 'Value');

            % === Read envelope data from table ===
            envData = get(handles.hlEnvelopeTable, 'Data');
            % Columns: U-wall, Area, CLTD, GlassArea, GlassU, SHGC, SolarRad

            Q_walls = 0;
            Q_roof = 0;
            Q_glassCond = 0;
            Q_glassSolar = 0;

            for wi = 1:size(envData, 1)
                U_wall = envData{wi, 1};
                A_wall = envData{wi, 2};
                CLTD_raw = envData{wi, 3};
                A_glass = envData{wi, 4};
                U_glass = envData{wi, 5};
                SHGC = envData{wi, 6};
                I_solar = envData{wi, 7};

                if any(isnan([U_wall A_wall CLTD_raw A_glass U_glass SHGC I_solar]))
                    continue;
                end

                % CLTD correction
                if autoCorrectCLTD && loadType == 1
                    if unitSys == 2  % SI
                        CLTD = CLTD_raw + (25.5 - T_in) + (T_out - 35);
                    else  % IP
                        CLTD = CLTD_raw + (78 - T_in) + (T_out - 95);
                    end
                    CLTD = max(CLTD, 0);
                else
                    if loadType == 2  % Heating: use simple ΔT
                        CLTD = T_in - T_out;  % positive when heating needed
                    else
                        CLTD = CLTD_raw;
                    end
                end

                % Wall/roof conduction: Q = U * A * CLTD  [W or Btu/hr]
                Q_surface = U_wall * A_wall * CLTD;

                % Glass conduction
                Q_gCond = U_glass * A_glass * CLTD;

                % Glass solar (cooling only)
                if loadType == 1  % Cooling
                    Q_gSolar = A_glass * SHGC * I_solar;
                else
                    Q_gSolar = 0;
                end

                if wi <= 4  % Walls (N/E/S/W)
                    Q_walls = Q_walls + Q_surface;
                else  % Roof
                    Q_roof = Q_surface;
                end
                Q_glassCond = Q_glassCond + Q_gCond;
                Q_glassSolar = Q_glassSolar + Q_gSolar;
            end

            % === Floor (optional) ===
            Q_floor = 0;
            if get(handles.hlIncludeFloor, 'Value')
                U_fl = str2double(get(handles.hlFloorU, 'String'));
                A_fl = str2double(get(handles.hlFloorArea, 'String'));
                T_gnd = str2double(get(handles.hlFloorTgnd, 'String'));
                if ~any(isnan([U_fl A_fl T_gnd]))
                    if loadType == 1  % Cooling
                        Q_floor = U_fl * A_fl * (T_gnd - T_in);
                    else  % Heating
                        Q_floor = U_fl * A_fl * (T_in - T_gnd);
                    end
                    Q_floor = max(Q_floor, 0);  % No negative floor load
                end
            end

            % === Internal gains ===
            W_light = str2double(get(handles.hlLighting, 'String'));
            div_light = str2double(get(handles.hlLightingDiv, 'String'));
            W_equip = str2double(get(handles.hlEquipment, 'String'));
            nOcc = str2double(get(handles.hlOccupants, 'String'));
            actIdx = get(handles.hlActivity, 'Value');
            W_moisture = str2double(get(handles.hlMoisture, 'String'));

            if isnan(W_light), W_light = 0; end
            if isnan(div_light), div_light = 1.0; end
            if isnan(W_equip), W_equip = 0; end
            if isnan(nOcc), nOcc = 0; end
            if isnan(W_moisture), W_moisture = 0; end

            % Activity: sensible/latent per person [W]
            activityData = [75 55; 75 75; 75 170; 170 255];
            q_sens_pp = activityData(actIdx, 1);
            q_lat_pp = activityData(actIdx, 2);

            Q_lighting = W_light * div_light;
            Q_equipment = W_equip;
            Q_people_sens = nOcc * q_sens_pp;
            Q_people_lat = nOcc * q_lat_pp;

            Q_intSens = Q_lighting + Q_equipment + Q_people_sens;
            Q_intLat = Q_people_lat + W_moisture;

            % For heating mode: internal gains are a CREDIT (reduce heating load)
            % They are kept as positive values here and subtracted in the totals

            % === Ventilation ===
            ventRate = str2double(get(handles.hlVentRate, 'String'));
            if isnan(ventRate), ventRate = 0; end

            if unitSys == 2  % SI
                Cp = 1006;      % J/(kg*K)
                hfg = 2501000;  % J/kg
                rho = 1.2;      % kg/m^3
                V_vent = ventRate / 1000;  % L/s -> m^3/s
                m_vent = V_vent * rho;
                Q_ventSens = m_vent * Cp * dT;     % W
                Q_ventLat = m_vent * hfg * dW;     % W
            else  % IP
                % Simplified: Q_s = 1.08 * CFM * dT [Btu/hr]
                %             Q_l = 0.68 * CFM * ΔW_grains [Btu/hr]
                dW_grains = dW * 7000;  % lb/lb -> grains/lb
                Q_ventSens = 1.08 * ventRate * dT;
                Q_ventLat = 0.68 * ventRate * dW_grains;
            end

            % === Infiltration ===
            infACH = str2double(get(handles.hlInfiltrationACH, 'String'));
            if isnan(infACH), infACH = 0; end

            roomVol = str2double(get(handles.roomVolumeInput, 'String'));
            if isnan(roomVol), roomVol = 0; end

            % Update room vol display on Tab 4
            if unitSys == 2
                set(handles.hlRoomVolDisplay, 'String', sprintf('%.0f m^3 (from Tab 2)', roomVol));
            else
                set(handles.hlRoomVolDisplay, 'String', sprintf('%.0f ft^3 (from Tab 2)', roomVol));
            end

            if unitSys == 2
                V_inf = roomVol * infACH / 3600;  % m^3/s
                m_inf = V_inf * rho;
                Q_infSens = m_inf * Cp * dT;
                Q_infLat = m_inf * hfg * dW;
            else
                V_inf_cfm = roomVol * infACH / 60;  % CFM
                dW_grains = dW * 7000;
                Q_infSens = 1.08 * V_inf_cfm * dT;
                Q_infLat = 0.68 * V_inf_cfm * dW_grains;
            end

            % === Totals ===
            if loadType == 1  % Cooling: everything adds up
                Q_sensTotal = Q_walls + Q_roof + Q_floor + Q_glassCond + Q_glassSolar + Q_intSens + abs(Q_ventSens) + abs(Q_infSens);
                Q_latTotal = Q_intLat + abs(Q_ventLat) + abs(Q_infLat);
            else  % Heating: internal gains are a credit (subtracted)
                Q_sensTotal = Q_walls + Q_roof + Q_floor + Q_glassCond + abs(Q_ventSens) + abs(Q_infSens) - Q_intSens;
                Q_latTotal = abs(Q_ventLat) + abs(Q_infLat) - Q_intLat;
                Q_sensTotal = max(Q_sensTotal, 0);  % Can't go negative
                Q_latTotal = max(Q_latTotal, 0);
            end
            Q_total = Q_sensTotal + Q_latTotal;

            if Q_total > 0
                SHR = Q_sensTotal / Q_total;
            else
                SHR = 1;
            end

            % === Display results ===
            if unitSys == 2
                unitStr = 'W';
                dispFactor = 1;  % Display in W
                % Switch to kW for totals if > 1000W
                if Q_total > 1000
                    totUnitStr = 'kW';
                    totFactor = 1/1000;
                else
                    totUnitStr = 'W';
                    totFactor = 1;
                end
            else
                unitStr = 'Btu/hr';
                dispFactor = 1;
                totUnitStr = 'Btu/hr';
                totFactor = 1;
            end

            Q_envelope = Q_walls + Q_roof;
            Q_glassTotal = Q_glassCond + Q_glassSolar;
            Q_ventTotal = abs(Q_ventSens) + abs(Q_ventLat);
            Q_infTotal = abs(Q_infSens) + abs(Q_infLat);

            % Write results into scrollable results table
            % In heating mode, show internal gains as negative (credit)
            if loadType == 2
                intSensDisp = -Q_intSens;
                intLatDisp = -Q_intLat;
                creditTag = ' (credit)';
            else
                intSensDisp = Q_intSens;
                intLatDisp = Q_intLat;
                creditTag = '';
            end

            resData = {sprintf('%.1f %s', Q_envelope * dispFactor, unitStr); ...
                       sprintf('%.1f %s', Q_floor * dispFactor, unitStr); ...
                       sprintf('%.1f %s', Q_glassTotal * dispFactor, unitStr); ...
                       sprintf('%.1f %s%s', intSensDisp * dispFactor, unitStr, creditTag); ...
                       sprintf('%.1f %s%s', intLatDisp * dispFactor, unitStr, creditTag); ...
                       sprintf('%.1f %s', Q_ventTotal * dispFactor, unitStr); ...
                       sprintf('%.1f %s', Q_infTotal * dispFactor, unitStr); ...
                       ''; ...
                       sprintf('%.2f %s', Q_sensTotal * totFactor, totUnitStr); ...
                       sprintf('%.2f %s', Q_latTotal * totFactor, totUnitStr); ...
                       sprintf('%.2f %s', Q_total * totFactor, totUnitStr); ...
                       sprintf('%.3f', SHR)};
            set(handles.hlResults.tableHandle, 'Data', resData);

            % Store in appData for integration with Tab 2
            appData.heatLoad.Q_sensible = Q_sensTotal;
            appData.heatLoad.Q_latent = Q_latTotal;
            appData.heatLoad.Q_total = Q_total;
            appData.heatLoad.SHR = SHR;
            appData.heatLoad.computed = true;
            appData.heatLoad.unitSystem = unitSys;
            setappdata(fig, 'appData', appData);

            if unitSys == 2
                updateStatus(sprintf('Heat Load: %.2f kW total (Qs=%.2f, Ql=%.2f, SHR=%.3f)', ...
                    Q_total/1000, Q_sensTotal/1000, Q_latTotal/1000, SHR));
            else
                updateStatus(sprintf('Heat Load: %.0f Btu/hr total (Qs=%.0f, Ql=%.0f, SHR=%.3f)', ...
                    Q_total, Q_sensTotal, Q_latTotal, SHR));
            end

        catch ME
            updateStatus(['Heat Load Error: ' ME.message]);
        end
    end

    function updateHeatLoadUnits()
        handles = guidata(fig);
        appData = getappdata(fig, 'appData');
        if appData.unitSystem == 2  % SI
            set(handles.hlOutdoorTempUnit, 'String', 'C');
            set(handles.hlIndoorTempUnit, 'String', 'C');
            set(handles.hlFloorTgndUnit, 'String', 'C');
            set(handles.hlVentRateUnit, 'String', 'L/s');
            set(handles.hlEnvUnitLabel, 'String', 'U=W/m2K | A=m2 | CLTD=C | I solar=W/m2');
            % Reset defaults to SI
            set(handles.hlOutdoorTemp, 'String', '35');
            set(handles.hlIndoorTemp, 'String', '24');
            set(handles.hlFloorTgnd, 'String', '18');
        else  % IP
            set(handles.hlOutdoorTempUnit, 'String', 'F');
            set(handles.hlIndoorTempUnit, 'String', 'F');
            set(handles.hlFloorTgndUnit, 'String', 'F');
            set(handles.hlVentRateUnit, 'String', 'CFM');
            set(handles.hlEnvUnitLabel, 'String', 'U=Btu/hrft2F | A=ft2 | CLTD=F | I solar=Btu/hrft2');
            % Reset defaults to IP
            set(handles.hlOutdoorTemp, 'String', '95');
            set(handles.hlIndoorTemp, 'String', '75');
            set(handles.hlFloorTgnd, 'String', '65');
        end
        % Reset heat load results table
        resetData = {'---'; '---'; '---'; '---'; '---'; '---'; '---'; ...
                     ''; '---'; '---'; '---'; '---'};
        set(handles.hlResults.tableHandle, 'Data', resetData);
        appData.heatLoad.computed = false;
        setappdata(fig, 'appData', appData);
    end

    function hlSendToProcessCallback(~, ~)
        appData = getappdata(fig, 'appData');
        handles = guidata(fig);

        if ~isfield(appData, 'heatLoad') || ~isfield(appData.heatLoad, 'computed') || ~appData.heatLoad.computed
            updateStatus('Calculate heat load first before sending to Process Analysis.');
            return;
        end

        % Switch to Process Analysis tab
        set(handles.tabGroup, 'SelectedTab', tab2);

        % Get heat load values for display
        if appData.heatLoad.unitSystem == 2
            Qt_hl = appData.heatLoad.Q_total / 1000;  % W -> kW
            unitStr = 'kW';
        else
            Qt_hl = appData.heatLoad.Q_total;
            unitStr = 'Btu/hr';
        end

        % If process has already been analysed, re-run it to pick up building load
        Qt_process = get(handles.procHandles.Qt, 'String');
        if ~strcmp(Qt_process, '---')
            analyseProcess([], []);
            updateStatus(sprintf('Building load (%.2f %s) included in equipment sizing. See Combined Capacity.', ...
                Qt_hl, unitStr));
        else
            updateStatus(sprintf('Building load: %.2f %s ready. Run Process Analysis to compute combined equipment sizing.', ...
                Qt_hl, unitStr));
        end
    end

    function chartClick(~, ~)
        handles = guidata(fig);
        appData = getappdata(fig, 'appData');

        pt = get(handles.ax, 'CurrentPoint');
        T = pt(1,1);
        W = pt(1,2);

        if T < appData.TRange(1) || T > appData.TRange(2) || W < 0 || W > 0.03
            updateStatus('Click is outside chart area. Please click within the chart bounds.');
            return;
        end

        Pws = psychro.saturationPressure(T, appData.unitSystem);
        W_sat = psychro.humidityRatio(Pws, appData.pressure, appData.unitSystem);

        if W > W_sat
            updateStatus('Invalid point: Above saturation curve. Please select a point below the blue line.');
            return;
        end

        props = psychro.calculateProperties(T, W, appData.pressure, appData.unitSystem);
        displayProperties(props, appData.unitSystem);
        updateCurrentMarker(T, W);

        handles.currentPoint = props;
        guidata(fig, handles);

        updateStatus(sprintf('Point selected: T=%.1f, W=%.5f', T, W));
        updateComfortAssessment();
    end

    function calculateFromInput(~, ~)
        handles = guidata(fig);
        appData = getappdata(fig, 'appData');

        firstValue = str2double(get(handles.firstPropInput, 'String'));
        secondValue = str2double(get(handles.secondPropInput, 'String'));

        prop1 = get(handles.firstPropDropdown, 'Value');
        prop2 = get(handles.secondPropDropdown, 'Value');

        if isnan(firstValue) || isnan(secondValue)
            updateStatus('Invalid input. Please enter valid numbers.');
            return;
        end

        if prop1 == prop2
            updateStatus('Cannot use the same property for both inputs.');
            return;
        end

        P = appData.pressure;
        unitSys = appData.unitSystem;

        propPair = sort([prop1, prop2]);
        propKey = propPair(1) * 10 + propPair(2);

        vals = struct();
        if prop1 == 1, vals.Tdb = firstValue; elseif prop2 == 1, vals.Tdb = secondValue; end
        if prop1 == 2, vals.Twb = firstValue; elseif prop2 == 2, vals.Twb = secondValue; end
        if prop1 == 3, vals.Tdp = firstValue; elseif prop2 == 3, vals.Tdp = secondValue; end
        if prop1 == 4, vals.W = firstValue; elseif prop2 == 4, vals.W = secondValue; end
        if prop1 == 5, vals.h = firstValue; elseif prop2 == 5, vals.h = secondValue; end
        if prop1 == 6, vals.RH = firstValue/100; elseif prop2 == 6, vals.RH = secondValue/100; end

        try
            switch propKey
                case 16  % Dry-Bulb + RH
                    T = vals.Tdb;
                    RH = vals.RH;
                    if RH < 0 || RH > 1
                        updateStatus('RH must be between 0 and 100%.');
                        return;
                    end
                    Pws = psychro.saturationPressure(T, unitSys);
                    W = psychro.humidityRatio(RH * Pws, P, unitSys);

                case 12  % Dry-Bulb + Wet-Bulb
                    T = vals.Tdb;
                    Twb = vals.Twb;
                    if Twb > T
                        updateStatus('Wet-bulb cannot exceed dry-bulb.');
                        return;
                    end
                    W = psychro.humidityRatioFromWetBulb(T, Twb, P, unitSys);

                case 13  % Dry-Bulb + Dew Point
                    T = vals.Tdb;
                    Tdp = vals.Tdp;
                    if Tdp > T
                        updateStatus('Dew point cannot exceed dry-bulb.');
                        return;
                    end
                    Pv = psychro.saturationPressure(Tdp, unitSys);
                    W = psychro.humidityRatio(Pv, P, unitSys);

                case 14  % Dry-Bulb + Humidity Ratio
                    T = vals.Tdb;
                    W = vals.W;

                case 15  % Dry-Bulb + Enthalpy
                    T = vals.Tdb;
                    h = vals.h;
                    W = psychro.humidityRatioFromEnthalpy(h, T, unitSys);

                case 26  % Wet-Bulb + RH
                    Twb = vals.Twb;
                    RH = vals.RH;
                    [T, W] = psychro.solveFromWetBulbAndRH(Twb, RH, P, unitSys);

                case 23  % Wet-Bulb + Dew Point
                    Twb = vals.Twb;
                    Tdp = vals.Tdp;
                    if Tdp > Twb
                        updateStatus('Dew point cannot exceed wet-bulb.');
                        return;
                    end
                    [T, W] = psychro.solveFromWetBulbAndDewPoint(Twb, Tdp, P, unitSys);

                case 24  % Wet-Bulb + Humidity Ratio
                    Twb = vals.Twb;
                    W = vals.W;
                    [T, ~] = psychro.solveFromWetBulbAndW(Twb, W, P, unitSys);

                case 25  % Wet-Bulb + Enthalpy
                    Twb = vals.Twb;
                    h = vals.h;
                    [T, W] = psychro.solveFromWetBulbAndEnthalpy(Twb, h, P, unitSys);

                case 36  % Dew Point + RH
                    Tdp = vals.Tdp;
                    RH = vals.RH;
                    Pv = psychro.saturationPressure(Tdp, unitSys);
                    Pws_T = Pv / RH;
                    T = psychro.temperatureFromSatPressure(Pws_T, unitSys);
                    W = psychro.humidityRatio(Pv, P, unitSys);

                case 34  % Dew Point + Humidity Ratio
                    Tdp = vals.Tdp;
                    W = vals.W;
                    Pv = psychro.saturationPressure(Tdp, unitSys);
                    W_check = psychro.humidityRatio(Pv, P, unitSys);
                    if abs(W - W_check) > 0.001
                        updateStatus('Warning: Dew point and W are inconsistent. Using Tdp.');
                        W = W_check;
                    end
                    % Derive T from W and Tdp: W fixes Pv, so RH = Pv/Pws(T)
                    % Use enthalpy approach: T = (h - W*hfg)/(Cp + W*Cpv)
                    % Since we don't have h, solve via RH: any T > Tdp is valid
                    % Pick T such that RH is reasonable (use Tdp to get Pv, then
                    % find T where Pws(T) gives a sensible RH)
                    % Default: user likely wants a specific T, but with only
                    % Tdp+W we need a third constraint. Use W to back-calculate.
                    Pv_from_W = W * P / (0.62198 + W);
                    T = psychro.temperatureFromSatPressure(Pv_from_W / 0.5, unitSys);  % assume ~50% RH

                case 35  % Dew Point + Enthalpy
                    Tdp = vals.Tdp;
                    h = vals.h;
                    Pv = psychro.saturationPressure(Tdp, unitSys);
                    W = psychro.humidityRatio(Pv, P, unitSys);
                    if unitSys == 1
                        T = (h - W * 1061) / (0.24 + W * 0.444);
                    else
                        T = (h - W * 2501) / (1.006 + W * 1.86);
                    end

                case 46  % Humidity Ratio + RH
                    W = vals.W;
                    RH = vals.RH;
                    Pv = W * P / (0.62198 + W);
                    Pws_T = Pv / RH;
                    T = psychro.temperatureFromSatPressure(Pws_T, unitSys);

                case 45  % Humidity Ratio + Enthalpy
                    W = vals.W;
                    h = vals.h;
                    if unitSys == 1
                        T = (h - W * 1061) / (0.24 + W * 0.444);
                    else
                        T = (h - W * 2501) / (1.006 + W * 1.86);
                    end

                case 56  % Enthalpy + RH
                    h = vals.h;
                    RH = vals.RH;
                    [T, W] = psychro.solveFromEnthalpyAndRH(h, RH, P, unitSys);

                otherwise
                    updateStatus('This property combination is not yet supported.');
                    return;
            end

            if W < 0 || W > 0.05 || isnan(W) || isnan(T)
                updateStatus('Invalid result. Check your input values.');
                return;
            end

            Pws = psychro.saturationPressure(T, unitSys);
            W_sat = psychro.humidityRatio(Pws, P, unitSys);
            if W > W_sat * 1.01
                updateStatus('Result exceeds saturation. Check inputs.');
                return;
            end

            props = psychro.calculateProperties(T, W, P, unitSys);
            displayProperties(props, unitSys);
            updateCurrentMarker(T, W);

            handles.currentPoint = props;
            guidata(fig, handles);

            updateStatus(sprintf('Calculated: T=%.2f, W=%.5f, RH=%.1f%%', T, W, props.RH*100));
            updateComfortAssessment();

        catch ME
            updateStatus(['Error: ' ME.message]);
        end
    end

    function markPoint(~, ~)
        handles = guidata(fig);
        appData = getappdata(fig, 'appData');

        if isempty(handles.currentPoint)
            updateStatus('No point selected. Click on chart or use manual input first.');
            return;
        end

        % Remove the current marker (black preview dot) since the point is now permanently marked
        if isfield(handles, 'currentMarkerHandle') && ~isempty(handles.currentMarkerHandle) && isvalid(handles.currentMarkerHandle)
            delete(handles.currentMarkerHandle);
        end
        handles.currentMarkerHandle = [];
        delete(findobj(handles.ax, 'Tag', 'currentMarker'));

        appData.pointCount = appData.pointCount + 1;
        hold(handles.ax, 'on');

        colors = [1 0 0; 0 0.5 0; 0 0 1; 0.8 0.4 0; 0.5 0 0.5; 0 0.7 0.7; 0.8 0 0.4; 0.4 0.4 0; 0 0.4 0.8; 0.6 0.2 0];
        colorIdx = mod(appData.pointCount - 1, size(colors, 1)) + 1;
        ptColor = colors(colorIdx, :);

        h = plot(handles.ax, handles.currentPoint.T, handles.currentPoint.W, ...
                 'o', 'MarkerSize', 6, 'MarkerFaceColor', ptColor, ...
                 'MarkerEdgeColor', ptColor, 'LineWidth', 1.5, ...
                 'HandleVisibility', 'off', 'HitTest', 'off', 'PickableParts', 'none', ...
                 'Tag', 'markedPoint');

        text(handles.ax, handles.currentPoint.T + 0.5, handles.currentPoint.W + 0.0005, ...
             sprintf('P%d', appData.pointCount), 'FontSize', 9, 'FontWeight', 'bold', ...
             'Color', ptColor, 'Tag', 'markedLabel', 'HitTest', 'off', 'PickableParts', 'none');

        handles.markerHandles(end+1) = h;
        if isempty(appData.markedPoints)
            appData.markedPoints = handles.currentPoint;
        else
            appData.markedPoints(end+1) = handles.currentPoint;
        end

        setappdata(fig, 'appData', appData);
        guidata(fig, handles);

        % Ensure all children pass clicks through to axes
        ch = get(handles.ax, 'Children');
        set(ch, 'HitTest', 'off');
        set(handles.ax, 'ButtonDownFcn', @chartClick);

        % Update process tab dropdowns
        updatePointDropdowns();

        updateStatus(sprintf('Point P%d marked at T=%.1f', appData.pointCount, handles.currentPoint.T));
    end

    function clearMarks(~, ~)
        try
            handles = guidata(fig);
            appData = getappdata(fig, 'appData');

            % Reset data
            appData.markedPoints = [];
            appData.pointCount = 0;
            appData.comfortLockedPoint = 0;
            handles.currentPoint = [];
            handles.currentMarkerHandle = [];
            handles.markerHandles = [];
            set(handles.comfortPointDropdown, 'Value', 1);

            % Save BEFORE redrawing
            setappdata(fig, 'appData', appData);
            guidata(fig, handles);

            % Explicitly delete ALL objects on axes (including HandleVisibility off)
            delete(findall(handles.ax, 'Type', 'line'));
            delete(findall(handles.ax, 'Type', 'text'));
            delete(findall(handles.ax, 'Type', 'patch'));

            % drawChart replots only chart lines
            % (markedPoints is now empty so nothing gets replotted)
            drawChart(fig);

            % Update process tab dropdowns
            updatePointDropdowns();
            resetProcessResults();
            resetProperties();

            updateStatus('All marks cleared.');
        catch ME
            updateStatus(['Clear error: ' ME.message]);
        end
    end

    function updatePointDropdowns()
        % Update the Point A and Point B dropdowns with current marked points
        handles = guidata(fig);
        appData = getappdata(fig, 'appData');

        if isempty(appData.markedPoints) || appData.pointCount == 0
            pointList = {'(No marked points)'};
        else
            pointList = cell(1, appData.pointCount);
            for i = 1:appData.pointCount
                p = appData.markedPoints(i);
                if appData.unitSystem == 2
                    pointList{i} = sprintf('P%d (T=%.1f C, W=%.5f)', i, p.T, p.W);
                else
                    pointList{i} = sprintf('P%d (T=%.1f F, W=%.5f)', i, p.T, p.W);
                end
            end
        end

        % Append Live Sensor Data option
        pointList{end+1} = 'Live Sensor Data';

        prevA = get(handles.pointADropdown, 'Value');
        prevB = get(handles.pointBDropdown, 'Value');
        set(handles.pointADropdown, 'String', pointList, 'Value', min(prevA, length(pointList)));
        set(handles.pointBDropdown, 'String', pointList, 'Value', min(prevB, length(pointList)));

        % Update Heat Load source dropdowns with same list
        hlSourceList = [{'Manual Input'}, pointList];
        prevOut = get(handles.hlOutdoorSource, 'Value');
        prevIn = get(handles.hlIndoorSource, 'Value');
        set(handles.hlOutdoorSource, 'String', hlSourceList, 'Value', min(prevOut, length(hlSourceList)));
        set(handles.hlIndoorSource, 'String', hlSourceList, 'Value', min(prevIn, length(hlSourceList)));

        % Update comfort point dropdown
        comfortList = [{'Current click'}, pointList];
        % If points were cleared, the list only has "Current click" + "(No marked points)"
        % Remove the "(No marked points)" entry
        if isempty(appData.markedPoints) || appData.pointCount == 0
            comfortList = {'Current click'};
        end
        prevVal = get(handles.comfortPointDropdown, 'Value');
        set(handles.comfortPointDropdown, 'String', comfortList);
        % Keep selection valid
        if prevVal > length(comfortList)
            set(handles.comfortPointDropdown, 'Value', 1);
            appData.comfortLockedPoint = 0;
            setappdata(fig, 'appData', appData);
        end
        updateComfortAssessment();
    end

    function liveProps = getLiveSensorProps()
        % Returns current live sensor data as a props struct, or empty
        liveData = getappdata(fig, 'lsLiveData');
        if isempty(liveData)
            liveProps = [];
            return;
        end
        appData = getappdata(fig, 'appData');
        liveProps = psychro.calculateProperties(liveData.T, liveData.W, appData.pressure, appData.unitSystem);
    end

    function isLive = isLiveSensorSelected(dropdownHandle)
        % Check if the "Live Sensor Data" option is selected
        items = get(dropdownHandle, 'String');
        val = get(dropdownHandle, 'Value');
        isLive = strcmp(items{val}, 'Live Sensor Data');
    end

    function lsRefreshProcessIfLive()
        % Re-run process analysis if either dropdown has Live Sensor selected
        handles = guidata(fig);
        if isLiveSensorSelected(handles.pointADropdown) || isLiveSensorSelected(handles.pointBDropdown)
            analyseProcess([], []);
        end
    end

    function analyseProcess(~, ~)
        handles = guidata(fig);
        appData = getappdata(fig, 'appData');

        idxA = get(handles.pointADropdown, 'Value');
        idxB = get(handles.pointBDropdown, 'Value');
        liveA = isLiveSensorSelected(handles.pointADropdown);
        liveB = isLiveSensorSelected(handles.pointBDropdown);

        % Get Point A
        if liveA
            pA = getLiveSensorProps();
            if isempty(pA)
                updateStatus('No live sensor data. Connect the sensor first.');
                return;
            end
        else
            if isempty(appData.markedPoints) || idxA > appData.pointCount
                updateStatus('Select a valid Point A or connect the live sensor.');
                return;
            end
            pA = appData.markedPoints(idxA);
        end

        % Get Point B
        if liveB
            pB = getLiveSensorProps();
            if isempty(pB)
                updateStatus('No live sensor data. Connect the sensor first.');
                return;
            end
        else
            if isempty(appData.markedPoints) || idxB > appData.pointCount
                updateStatus('Select a valid Point B or connect the live sensor.');
                return;
            end
            pB = appData.markedPoints(idxB);
        end

        if ~liveA && ~liveB && idxA == idxB
            updateStatus('Point A and Point B must be different.');
            return;
        end

        unitSys = appData.unitSystem;
        P = appData.pressure;

        % Calculate flow rates from room volume and ACH
        roomVol = str2double(get(handles.roomVolumeInput, 'String'));
        ACH = str2double(get(handles.achInput, 'String'));
        if isnan(roomVol) || roomVol <= 0
            updateStatus('Invalid room volume. Please enter a positive number.');
            return;
        end
        if isnan(ACH) || ACH <= 0
            updateStatus('Invalid ACH. Please enter a positive number.');
            return;
        end

        % Volumetric flow rate
        if unitSys == 2  % SI: m^3 -> m^3/s
            V_dot = roomVol * ACH / 3600;
            m_dot = V_dot / pA.v;  % kg/s (using specific volume at Point A)
            set(handles.volFlowDisplay, 'String', sprintf('%.4f m^3/s (%.1f L/s)', V_dot, V_dot*1000));
            set(handles.massFlowDisplay, 'String', sprintf('%.4f kg/s', m_dot));
        else  % IP: ft^3 -> ft^3/min (CFM)
            V_dot = roomVol * ACH / 60;  % CFM
            m_dot = V_dot / pA.v;  % lb/min (using specific volume at Point A)
            set(handles.volFlowDisplay, 'String', sprintf('%.1f CFM', V_dot));
            set(handles.massFlowDisplay, 'String', sprintf('%.3f lb/min', m_dot));
        end
        flowRate = m_dot;
        set(handles.flowRateInput, 'String', num2str(flowRate));

        % Calculate changes
        dT = pB.T - pA.T;
        dW = pB.W - pA.W;
        dh = pB.h - pA.h;

        % Identify process type
        Wtol = 0.0001;  % tolerance for humidity ratio change
        Ttol = 0.5;     % tolerance for temperature change

        if abs(dW) < Wtol && dT > Ttol
            processType = 'Sensible Heating';
        elseif abs(dW) < Wtol && dT < -Ttol
            processType = 'Sensible Cooling';
        elseif abs(dT) < Ttol && dW > 0
            processType = 'Humidification';
        elseif abs(dT) < Ttol && dW < 0
            processType = 'Dehumidification';
        elseif dT > Ttol && dW > 0
            processType = 'Heating + Humidification';
        elseif dT < -Ttol && dW < 0
            processType = 'Cooling + Dehumidification';
        elseif dT > Ttol && dW < 0
            processType = 'Heating + Dehumidification';
        elseif dT < -Ttol && dW > 0
            processType = 'Cooling + Humidification';
        else
            processType = 'No Significant Change';
        end

        % Energy calculations
        if unitSys == 2  % SI
            Cp_air = 1.006;  % kJ/(kg*K)
            hfg = 2501;      % kJ/kg
            Qs = flowRate * Cp_air * dT;  % kW
            Ql = flowRate * hfg * dW;     % kW
            Qt = flowRate * dh;           % kW
            mw = flowRate * abs(dW);      % kg/s moisture
        else  % IP
            Cp_air = 0.24;   % Btu/(lb*F)
            hfg = 1061;      % Btu/lb
            Qs = flowRate * Cp_air * dT;  % Btu/min
            Ql = flowRate * hfg * dW;     % Btu/min
            Qt = flowRate * dh;           % Btu/min
            mw = flowRate * abs(dW);      % lb/min moisture
        end

        % Sensible Heat Ratio
        if abs(Qt) > 0.001
            SHR = abs(Qs) / abs(Qt);
        else
            SHR = 1;
        end

        % Display results
        set(handles.procHandles.procType, 'String', processType);

        if unitSys == 2
            set(handles.procHandles.dT, 'String', sprintf('%.2f C', dT));
            set(handles.procHandles.dW, 'String', sprintf('%.5f kg/kg', dW));
            set(handles.procHandles.dh, 'String', sprintf('%.2f kJ/kg', dh));
            set(handles.procHandles.Qs, 'String', sprintf('%.2f kW', Qs));
            set(handles.procHandles.Ql, 'String', sprintf('%.2f kW', Ql));
            set(handles.procHandles.Qt, 'String', sprintf('%.2f kW', Qt));
            set(handles.procHandles.SHR, 'String', sprintf('%.3f', SHR));
            set(handles.procHandles.mw, 'String', sprintf('%.5f kg/s', mw));
            set(handles.procHandles.Ta, 'String', sprintf('%.2f C', pA.T));
            set(handles.procHandles.Tb, 'String', sprintf('%.2f C', pB.T));
        else
            set(handles.procHandles.dT, 'String', sprintf('%.2f F', dT));
            set(handles.procHandles.dW, 'String', sprintf('%.5f lb/lb', dW));
            set(handles.procHandles.dh, 'String', sprintf('%.2f Btu/lb', dh));
            set(handles.procHandles.Qs, 'String', sprintf('%.2f Btu/min', Qs));
            set(handles.procHandles.Ql, 'String', sprintf('%.2f Btu/min', Ql));
            set(handles.procHandles.Qt, 'String', sprintf('%.2f Btu/min', Qt));
            set(handles.procHandles.SHR, 'String', sprintf('%.3f', SHR));
            set(handles.procHandles.mw, 'String', sprintf('%.5f lb/min', mw));
            set(handles.procHandles.Ta, 'String', sprintf('%.2f F', pA.T));
            set(handles.procHandles.Tb, 'String', sprintf('%.2f F', pB.T));
        end

        % Colour code the process type
        if contains(processType, 'Heating')
            set(handles.procHandles.procType, 'ForegroundColor', [0.8 0 0]);
        elseif contains(processType, 'Cooling')
            set(handles.procHandles.procType, 'ForegroundColor', [0 0 0.8]);
        else
            set(handles.procHandles.procType, 'ForegroundColor', [0 0.5 0]);
        end

        % === ADP Calculation (must come before reheat/sizing) ===
        % When heat load data exists, use Tab 4 indoor conditions as the room
        % condition (SHR line origin). Otherwise fall back to Point A.
        if isfield(appData, 'heatLoad') && isfield(appData.heatLoad, 'computed') && appData.heatLoad.computed
            SHR_for_ADP = appData.heatLoad.SHR;
            % Get indoor design conditions from Tab 4
            T_room_hl = str2double(get(handles.hlIndoorTemp, 'String'));
            RH_room_hl = str2double(get(handles.hlIndoorRH, 'String')) / 100;
            if ~isnan(T_room_hl) && ~isnan(RH_room_hl) && RH_room_hl > 0
                Pws_room_hl = psychro.saturationPressure(T_room_hl, unitSys);
                Pv_room_hl = RH_room_hl * Pws_room_hl;
                W_room_hl = psychro.humidityRatio(Pv_room_hl, P, unitSys);
                T_shr_origin = T_room_hl;
                W_shr_origin = W_room_hl;
            else
                T_shr_origin = pA.T;
                W_shr_origin = pA.W;
            end
        else
            SHR_for_ADP = SHR;
            T_shr_origin = pA.T;
            W_shr_origin = pA.W;
        end

        % Find ADP: intersection of SHR line from ROOM condition with saturation curve
        [T_adp, W_adp] = psychro.findADP(T_shr_origin, W_shr_origin, SHR_for_ADP, P, unitSys);

        if ~isnan(T_adp)
            if unitSys == 2
                set(handles.procHandles.ADP, 'String', sprintf('%.1f °C (W=%.5f)', T_adp, W_adp));
            else
                set(handles.procHandles.ADP, 'String', sprintf('%.1f °F (W=%.5f)', T_adp, W_adp));
            end
        else
            set(handles.procHandles.ADP, 'String', 'N/A (SHR=1 or invalid)');
        end

        % Read bypass factor
        BF = str2double(get(handles.bypassFactorInput, 'String'));
        if isnan(BF) || BF < 0 || BF > 1
            BF = 0.10;
        end

        % === Reheat Load Calculation ===
        % When ADP is known, reheat = energy to warm air from ADP to off-coil/supply
        Q_reheat = 0;
        if ~isnan(T_adp)
            T_offcoil_calc = T_adp + BF * (T_shr_origin - T_adp);
            if unitSys == 2
                Cp_rh = 1.006;  % kJ/(kg·K)
                Q_reheat = flowRate * Cp_rh * (T_offcoil_calc - T_adp);  % kW
                set(handles.procHandles.Qreheat, 'String', sprintf('%.2f kW', Q_reheat));
            else
                Cp_rh = 0.24;
                Q_reheat = flowRate * Cp_rh * (T_offcoil_calc - T_adp);  % Btu/min
                set(handles.procHandles.Qreheat, 'String', sprintf('%.2f Btu/min', Q_reheat));
            end
            set(handles.procHandles.Qreheat, 'ForegroundColor', [0.85 0.3 0.1]);
        else
            set(handles.procHandles.Qreheat, 'String', 'N/A (no ADP)');
        end

        % === Equipment Sizing Calculations ===
        V_dot_A = flowRate * pA.v;  % volumetric flow at inlet
        V_dot_B = flowRate * pB.v;  % volumetric flow at outlet
        designFactor = 1.15;

        % Process capacity including reheat penalty
        Qt_proc_abs = abs(Qt) + abs(Q_reheat);

        % --- Check if Tab 4 building load has been computed ---
        hasHeatLoad = isfield(appData, 'heatLoad') && ...
                      isfield(appData.heatLoad, 'computed') && ...
                      appData.heatLoad.computed;
        Qt_bldg_kW = 0;

        if hasHeatLoad
            if unitSys == 2
                Qt_bldg_kW = appData.heatLoad.Q_total / 1000;  % W -> kW
            else
                Qt_bldg_kW = appData.heatLoad.Q_total / 3412.14;  % Btu/hr -> kW (internal)
            end
        end

        if unitSys == 2  % SI
            Qt_proc_kW = Qt_proc_abs;
            Qt_combined_kW = Qt_proc_kW + Qt_bldg_kW;
            Qt_proc_tons = Qt_proc_kW / 3.517;
            Qt_combined_tons = Qt_combined_kW / 3.517;
            designCap = Qt_combined_kW * designFactor;
            designCap_tons = Qt_combined_tons * designFactor;
            moisture_Lhr = mw * 3600;

            set(handles.procHandles.VdotA, 'String', sprintf('%.4f m^3/s (%.1f L/s)', V_dot_A, V_dot_A*1000));
            set(handles.procHandles.VdotB, 'String', sprintf('%.4f m^3/s (%.1f L/s)', V_dot_B, V_dot_B*1000));
            if Q_reheat > 0.001
                set(handles.procHandles.reqCapacity, 'String', sprintf('%.2f kW (%.2f+%.2f reheat)', Qt_proc_kW, abs(Qt), Q_reheat));
            else
                set(handles.procHandles.reqCapacity, 'String', sprintf('%.2f kW (%.2f tons)', Qt_proc_kW, Qt_proc_tons));
            end

            if hasHeatLoad
                set(handles.procHandles.bldgLoad, 'String', sprintf('%.2f kW', Qt_bldg_kW));
                set(handles.procHandles.bldgLoad, 'ForegroundColor', [0.6 0.3 0]);
                set(handles.procHandles.combinedCapacity, 'String', sprintf('%.2f kW (%.2f tons)', Qt_combined_kW, Qt_combined_tons));
                set(handles.procHandles.combinedCapacity, 'ForegroundColor', [0.8 0 0]);
            else
                set(handles.procHandles.bldgLoad, 'String', 'Not computed (run Tab 4)');
                set(handles.procHandles.bldgLoad, 'ForegroundColor', [0.6 0.6 0.6]);
                set(handles.procHandles.combinedCapacity, 'String', sprintf('%.2f kW (process only)', Qt_proc_kW));
                set(handles.procHandles.combinedCapacity, 'ForegroundColor', [0.6 0.6 0.6]);
            end

            set(handles.procHandles.designCapacity, 'String', sprintf('%.2f kW (%.2f tons)', designCap, designCap_tons));
            set(handles.procHandles.moistureRate, 'String', sprintf('%.3f L/hr', moisture_Lhr));
        else  % IP
            Qt_proc_Btuhr = Qt_proc_abs * 60;
            Qt_bldg_Btuhr = Qt_bldg_kW * 3412.14;
            Qt_combined_Btuhr = Qt_proc_Btuhr + Qt_bldg_Btuhr;
            Qt_proc_tons = Qt_proc_Btuhr / 12000;
            Qt_combined_tons = Qt_combined_Btuhr / 12000;
            designCap_Btuhr = Qt_combined_Btuhr * designFactor;
            designCap_tons = Qt_combined_tons * designFactor;
            moisture_galhr = mw * 60 / 8.345;

            set(handles.procHandles.VdotA, 'String', sprintf('%.1f CFM', V_dot_A));
            set(handles.procHandles.VdotB, 'String', sprintf('%.1f CFM', V_dot_B));
            if Q_reheat > 0.001
                set(handles.procHandles.reqCapacity, 'String', sprintf('%.0f Btu/hr (%.0f+%.0f reheat)', Qt_proc_Btuhr, abs(Qt)*60, Q_reheat*60));
            else
                set(handles.procHandles.reqCapacity, 'String', sprintf('%.0f Btu/hr (%.2f tons)', Qt_proc_Btuhr, Qt_proc_tons));
            end

            if hasHeatLoad
                set(handles.procHandles.bldgLoad, 'String', sprintf('%.0f Btu/hr', Qt_bldg_Btuhr));
                set(handles.procHandles.bldgLoad, 'ForegroundColor', [0.6 0.3 0]);
                set(handles.procHandles.combinedCapacity, 'String', sprintf('%.0f Btu/hr (%.2f tons)', Qt_combined_Btuhr, Qt_combined_tons));
                set(handles.procHandles.combinedCapacity, 'ForegroundColor', [0.8 0 0]);
            else
                set(handles.procHandles.bldgLoad, 'String', 'Not computed (run Tab 4)');
                set(handles.procHandles.bldgLoad, 'ForegroundColor', [0.6 0.6 0.6]);
                set(handles.procHandles.combinedCapacity, 'String', sprintf('%.0f Btu/hr (process only)', Qt_proc_Btuhr));
                set(handles.procHandles.combinedCapacity, 'ForegroundColor', [0.6 0.6 0.6]);
            end

            set(handles.procHandles.designCapacity, 'String', sprintf('%.0f Btu/hr (%.2f tons)', designCap_Btuhr, designCap_tons));
            set(handles.procHandles.moistureRate, 'String', sprintf('%.3f gal/hr', moisture_galhr));
        end

        % === HVAC Equipment Type Recommendation ===
        % Use combined SHR (process + building) if heat load is available
        if hasHeatLoad && Qt_combined_kW > 0
            combinedSHR = (abs(Qs) + appData.heatLoad.Q_sensible/1000) / Qt_combined_kW;
        else
            combinedSHR = SHR;
        end

        if strcmp(processType, 'Sensible Heating')
            equipStr = 'Furnace / Heat Pump / Electric Heater';
        elseif strcmp(processType, 'Sensible Cooling')
            equipStr = 'Split AC / Packaged Cooling Unit';
        elseif strcmp(processType, 'Cooling + Dehumidification')
            if combinedSHR < 0.7
                equipStr = 'DX Coil + Desiccant/Dedicated Dehumid.';
            else
                equipStr = 'Split AC / DX Cooling Coil (Standard)';
            end
        elseif strcmp(processType, 'Heating + Humidification')
            equipStr = 'Heat Pump + Steam/Spray Humidifier';
        elseif strcmp(processType, 'Cooling + Humidification')
            equipStr = 'Evaporative Cooler (Swamp Cooler)';
        elseif strcmp(processType, 'Heating + Dehumidification')
            equipStr = 'Heat Pump + Desiccant Dehumidifier';
        elseif strcmp(processType, 'Humidification')
            equipStr = 'Steam / Spray Humidifier';
        elseif strcmp(processType, 'Dehumidification')
            equipStr = 'Desiccant / Dedicated Dehumidifier';
        else
            equipStr = 'N/A';
        end
        set(handles.procHandles.equipType, 'String', equipStr);
        set(handles.procHandles.equipType, 'ForegroundColor', [0.6 0.3 0]);

        % Auto-draw the process on chart (with ADP and SHR line info)
        drawProcessOnChart(pA, pB, processType, Qs, Ql, Qt, SHR_for_ADP, unitSys, P, T_adp, W_adp, BF, T_shr_origin, W_shr_origin);

        % === Status bar: combined sizing summary ===
        if unitSys == 2
            if hasHeatLoad
                statusMsg = sprintf('Process: %.2f kW + Building: %.2f kW = Combined: %.2f kW | Design (x1.15): %.2f kW', ...
                    Qt_proc_kW, Qt_bldg_kW, Qt_combined_kW, designCap);
            else
                statusMsg = sprintf('Process: %s | Qt=%.2f kW | Design: %.2f kW (no building load - run Tab 4)', ...
                    processType, Qt_proc_kW, Qt_proc_kW * designFactor);
            end
        else
            if hasHeatLoad
                statusMsg = sprintf('Process: %.0f + Building: %.0f = Combined: %.0f Btu/hr | Design: %.0f Btu/hr', ...
                    Qt_proc_Btuhr, Qt_bldg_Btuhr, Qt_combined_Btuhr, designCap_Btuhr);
            else
                statusMsg = sprintf('Process: %s | Qt=%.0f Btu/hr | Design: %.0f Btu/hr (no building load)', ...
                    processType, Qt_proc_Btuhr, Qt_proc_Btuhr * designFactor);
            end
        end

        updateStatus(statusMsg);
    end

    function drawProcess(~, ~)
        % Manual draw button - triggers analyse first then draws
        handles = guidata(fig);
        appData = getappdata(fig, 'appData');

        if isempty(appData.markedPoints) || appData.pointCount < 2
            updateStatus('Need at least 2 marked points.');
            return;
        end

        idxA = get(handles.pointADropdown, 'Value');
        idxB = get(handles.pointBDropdown, 'Value');

        if idxA == idxB
            updateStatus('Point A and Point B must be different.');
            return;
        end

        % Just call analyse which now auto-draws
        analyseProcess([], []);
    end

    function drawProcessOnChart(pA, pB, processType, Qs, Ql, Qt, SHR, unitSys, P, T_adp, W_adp, BF, T_shr_origin, W_shr_origin)
        % T_adp, W_adp, BF, T_shr_origin, W_shr_origin are optional
        if nargin < 10, T_adp = NaN; end
        if nargin < 11, W_adp = NaN; end
        if nargin < 12, BF = 0.10; end
        if nargin < 13, T_shr_origin = pA.T; end
        if nargin < 14, W_shr_origin = pA.W; end

        handles = guidata(fig);

        % Clear existing process graphics
        clearProcessLine();

        hold(handles.ax, 'on');

        % Fade background chart elements so the process stands out
        fadeChartBackground();

        % Choose process colour based on type
        if contains(processType, 'Heating')
            procColor = [0.85 0.15 0.15];   % red
            arrowColor = [0.7 0 0];
        elseif contains(processType, 'Cooling')
            procColor = [0.15 0.15 0.85];   % blue
            arrowColor = [0 0 0.7];
        elseif contains(processType, 'Humidification')
            procColor = [0.1 0.7 0.3];      % green
            arrowColor = [0 0.5 0.2];
        else
            procColor = [0.6 0 0.6];        % purple
            arrowColor = [0.4 0 0.4];
        end

        dT = pB.T - pA.T;
        dW = pB.W - pA.W;

        % === Cooling + Dehumidification: three-phase path ===
        if strcmp(processType, 'Cooling + Dehumidification')
            % Determine the coil target point:
            % If SHR-derived ADP is available, use it (proper HVAC design).
            % Otherwise fall back to outlet dew point (legacy behaviour).
            if ~isnan(T_adp) && ~isnan(W_adp)
                % SHR-derived ADP — the coil cools to this point on the sat curve
                T_coil_target = T_adp;
                W_coil_target = W_adp;
                useADP = true;

                % Off-coil (supply) condition via BF
                T_offcoil = T_adp + BF * (T_shr_origin - T_adp);
                W_offcoil = W_adp + BF * (W_shr_origin - W_adp);
            else
                % Legacy: use dew point of outlet air
                Pv_B = pB.W * P / (0.62198 + pB.W);
                T_coil_target = psychro.calculateDewPoint(Pv_B, unitSys);
                W_coil_target = pB.W;
                useADP = false;
                T_offcoil = pB.T;
                W_offcoil = pB.W;
            end

            % Phase 1: Find dew point of inlet air (where cooling starts condensing)
            Pv_inlet = pA.W * P / (0.62198 + pA.W);
            T_dp_room = psychro.calculateDewPoint(Pv_inlet, unitSys);
            T_dp_room = min(T_dp_room, pA.T);

            % Phase 1: Sensible cooling — horizontal from Point A to its dew point
            plot(handles.ax, [pA.T T_dp_room], [pA.W pA.W], ...
                 '-', 'Color', procColor, 'LineWidth', 2.0, 'Tag', 'processLine', 'HandleVisibility', 'off');

            % Phase 2: Follow saturation curve from room dew point down to ADP
            nPts = 50;
            curveT = linspace(T_dp_room, T_coil_target, nPts);
            curveW = zeros(size(curveT));
            for ci = 1:nPts
                Pws_c = psychro.saturationPressure(curveT(ci), unitSys);
                curveW(ci) = psychro.humidityRatio(Pws_c, P, unitSys);
            end
            plot(handles.ax, curveT, curveW, ...
                 '-', 'Color', procColor, 'LineWidth', 2.0, 'Tag', 'processLine', 'HandleVisibility', 'off');

            % Draw dashed SHR slope line FIRST (behind reheat) from room to ADP
            if useADP
                plot(handles.ax, [T_shr_origin T_adp], [W_shr_origin W_adp], ...
                     '--', 'Color', [0.8 0.4 0.0], 'LineWidth', 1.5, ...
                     'Tag', 'processLine', 'HandleVisibility', 'off');
                midSHR_T = (T_shr_origin + T_adp) / 2;
                midSHR_W = (W_shr_origin + W_adp) / 2;
                text(handles.ax, midSHR_T + 0.5, midSHR_W + 0.0006, ...
                     sprintf('SHR line (%.3f)', SHR), ...
                     'FontSize', 6, 'FontWeight', 'bold', 'Color', [0.6 0.3 0.0], ...
                     'BackgroundColor', [1 1 0.9 0.7], 'EdgeColor', [0.8 0.5 0.2], ...
                     'Margin', 2, 'Tag', 'processLabel');
            end

            % Phase 3: Reheat — from ADP along SHR line to off-coil/supply point
            % Drawn ON TOP of the dashed SHR line so it is clearly visible
            plot(handles.ax, [T_coil_target T_offcoil], [W_coil_target W_offcoil], ...
                 '-', 'Color', [0.85 0.4 0.15], 'LineWidth', 2.5, 'Tag', 'processLine', 'HandleVisibility', 'off');

            % Mark the inlet dew point (Phase 1 -> 2 transition)
            plot(handles.ax, T_dp_room, pA.W, 'diamond', 'MarkerSize', 5, ...
                 'MarkerFaceColor', [0.9 0.9 0.2], 'MarkerEdgeColor', [0.4 0.4 0], ...
                 'LineWidth', 1, 'Tag', 'processLine', 'HandleVisibility', 'off');

            % Mark the ADP / coil target (Phase 2 -> 3 transition)
            plot(handles.ax, T_coil_target, W_coil_target, 'pentagram', 'MarkerSize', 9, ...
                 'MarkerFaceColor', [1.0 0.6 0.0], 'MarkerEdgeColor', [0.5 0.2 0.0], ...
                 'LineWidth', 1.2, 'Tag', 'processLine', 'HandleVisibility', 'off');

            % Off-coil square marker removed to reduce chart clutter

            % Label room dew point
            if unitSys == 2
                dpLabelA = sprintf('Dew Pt = %.1f °C', T_dp_room);
            else
                dpLabelA = sprintf('Dew Pt = %.1f °F', T_dp_room);
            end
            text(handles.ax, T_dp_room, pA.W + 0.0006, dpLabelA, ...
                 'FontSize', 6, 'Color', [0.4 0.4 0], 'FontWeight', 'bold', ...
                 'HorizontalAlignment', 'center', ...
                 'BackgroundColor', [1 1 1 0.6], 'EdgeColor', [0.7 0.7 0.4], ...
                 'Margin', 2, 'Tag', 'processLabel');

            % Combined ADP + Off-coil label (single label to avoid clutter)
            if useADP && BF > 0.001
                if unitSys == 2
                    adpOffStr = sprintf('ADP=%.1f°C  Off-coil=%.1f°C (BF=%.2f)', ...
                                        T_coil_target, T_offcoil, BF);
                else
                    adpOffStr = sprintf('ADP=%.1f°F  Off-coil=%.1f°F (BF=%.2f)', ...
                                        T_coil_target, T_offcoil, BF);
                end
            else
                if unitSys == 2
                    adpOffStr = sprintf('ADP = %.1f °C', T_coil_target);
                else
                    adpOffStr = sprintf('ADP = %.1f °F', T_coil_target);
                end
            end
            text(handles.ax, T_coil_target - 0.5, W_coil_target - 0.0008, adpOffStr, ...
                 'FontSize', 6, 'Color', [0.5 0.2 0.0], 'FontWeight', 'bold', ...
                 'HorizontalAlignment', 'right', ...
                 'BackgroundColor', [1 1 0.85 0.8], 'EdgeColor', [0.8 0.5 0.1], ...
                 'Margin', 2, 'Tag', 'processLabel');

            % Phase labels with energy values
            if unitSys == 2
                qsStr = sprintf('Qs=%.1f kW', Qs);
                qlStr = sprintf('Ql=%.1f kW', Ql);
            else
                qsStr = sprintf('Qs=%.1f', Qs);
                qlStr = sprintf('Ql=%.1f', Ql);
            end

            % Phase 1 label (sensible cooling — horizontal)
            midSensT = (pA.T + T_dp_room) / 2;
            text(handles.ax, midSensT, pA.W + 0.0004, ['1: Sensible (' qsStr ')'], ...
                 'FontSize', 6, 'FontWeight', 'bold', 'Color', [0.1 0.1 0.7], ...
                 'HorizontalAlignment', 'center', ...
                 'BackgroundColor', [1 1 1 0.6], 'EdgeColor', [0.6 0.6 0.8], ...
                 'Margin', 2, 'Tag', 'processLabel');

            % Phase 2 label (saturation curve)
            midCurveIdx = round(nPts * 0.5);
            text(handles.ax, curveT(midCurveIdx) - 1.2, curveW(midCurveIdx) - 0.0004, ['2: Coil (' qlStr ')'], ...
                 'FontSize', 6, 'FontWeight', 'bold', 'Color', [0.1 0.1 0.7], ...
                 'HorizontalAlignment', 'center', ...
                 'BackgroundColor', [1 1 1 0.6], 'EdgeColor', [0.6 0.6 0.8], ...
                 'Margin', 2, 'Tag', 'processLabel');

            % Reheat label removed to reduce chart clutter

            % Arrowhead at off-coil / supply point
            drawArrowhead(T_coil_target, W_coil_target, T_offcoil, W_offcoil, [0.85 0.4 0.15]);

        else
            % === All other processes: straight line from A to B ===
            plot(handles.ax, [pA.T pB.T], [pA.W pB.W], ...
                 '-', 'Color', procColor, 'LineWidth', 2.0, 'Tag', 'processLine', 'HandleVisibility', 'off');

            % Show decomposition lines for combined processes
            if contains(processType, 'Sensible') || strcmp(processType, 'No Significant Change')
                % Pure sensible or no change: no decomposition needed
            elseif strcmp(processType, 'Humidification') || strcmp(processType, 'Dehumidification')
                % Pure humidity change: no decomposition needed
            else
                % Combined process: dashed sensible (horizontal) + latent (vertical)
                plot(handles.ax, [pA.T pB.T], [pA.W pA.W], ...
                     '--', 'Color', [0.7 0.3 0.3], 'LineWidth', 0.8, 'Tag', 'processLine', 'HandleVisibility', 'off');
                plot(handles.ax, [pB.T pB.T], [pA.W pB.W], ...
                     '--', 'Color', [0.3 0.3 0.7], 'LineWidth', 0.8, 'Tag', 'processLine', 'HandleVisibility', 'off');

                midSensT = (pA.T + pB.T) / 2;
                midLatW = (pA.W + pB.W) / 2;
                if unitSys == 2
                    qsLabel = sprintf('Qs=%.1f kW', Qs);
                    qlLabel = sprintf('Ql=%.1f kW', Ql);
                else
                    qsLabel = sprintf('Qs=%.1f', Qs);
                    qlLabel = sprintf('Ql=%.1f', Ql);
                end
                text(handles.ax, midSensT, pA.W - 0.0005, qsLabel, ...
                     'FontSize', 6, 'FontWeight', 'bold', 'Color', [0.7 0.2 0.2], ...
                     'HorizontalAlignment', 'center', ...
                     'BackgroundColor', [1 1 1 0.6], 'EdgeColor', [0.8 0.6 0.6], ...
                     'Margin', 2, 'Tag', 'processLabel');
                text(handles.ax, pB.T + 0.5, midLatW, qlLabel, ...
                     'FontSize', 6, 'FontWeight', 'bold', 'Color', [0.2 0.2 0.7], ...
                     'HorizontalAlignment', 'left', ...
                     'BackgroundColor', [1 1 1 0.6], 'EdgeColor', [0.6 0.6 0.8], ...
                     'Margin', 2, 'Tag', 'processLabel');
            end

            % Arrowhead at B
            drawArrowhead(pA.T, pA.W, pB.T, pB.W, arrowColor);
        end

        % Process type label near the midpoint of the line
        midT = (pA.T + pB.T) / 2;
        midW = (pA.W + pB.W) / 2;
        text(handles.ax, midT, midW + 0.0012, processType, ...
             'FontSize', 7, 'FontWeight', 'bold', 'Color', arrowColor, ...
             'HorizontalAlignment', 'center', ...
             'BackgroundColor', [1 1 1 0.6], 'EdgeColor', arrowColor, ...
             'Tag', 'processLabel');

        % Add energy summary annotation box in top-right of chart
        if unitSys == 2
            energyStr = sprintf('Qt=%.2f kW  SHR=%.3f', Qt, SHR);
        else
            energyStr = sprintf('Qt=%.2f Btu/min  SHR=%.3f', Qt, SHR);
        end
        xPos = handles.ax.XLim(2) - 0.02 * diff(handles.ax.XLim);
        yPosChart = handles.ax.YLim(2) - 0.06 * diff(handles.ax.YLim);
        text(handles.ax, xPos, yPosChart, energyStr, ...
             'FontSize', 8, 'FontWeight', 'bold', 'Color', [0.2 0.2 0.2], ...
             'HorizontalAlignment', 'right', ...
             'BackgroundColor', [1 1 0.85], 'EdgeColor', [0.5 0.5 0.5], ...
             'Tag', 'processLabel');

        % SHR line / ADP / off-coil markers are only drawn for Cooling + Dehumidification
        % (handled in the three-phase section above). No SHR overlay for other processes.

        hold(handles.ax, 'off');

        % Re-enable click on children
        ch = get(handles.ax, 'Children');
        set(ch, 'HitTest', 'off');
    end

    function drawArrowhead(T1, W1, T2, W2, color)
        % Draw a proper arrowhead at point (T2, W2)
        handles = guidata(fig);

        dT = T2 - T1;
        dW = W2 - W1;

        % Normalize in chart coordinates (scale W by aspect ratio)
        Tscale = diff(handles.ax.XLim);
        Wscale = diff(handles.ax.YLim);
        dT_n = dT / Tscale;
        dW_n = dW / Wscale;
        len_n = sqrt(dT_n^2 + dW_n^2);

        if len_n < 1e-10, return; end

        uT_n = dT_n / len_n;
        uW_n = dW_n / len_n;

        % Arrow size in normalized units
        aLen = 0.018;
        aWidth = 0.007;

        % Arrowhead base center (behind the tip)
        baseT = T2 - aLen * uT_n * Tscale;
        baseW = W2 - aLen * uW_n * Wscale;

        % Perpendicular direction
        pT_n = -uW_n;
        pW_n = uT_n;

        % Two wing points
        wing1T = baseT + aWidth * pT_n * Tscale;
        wing1W = baseW + aWidth * pW_n * Wscale;
        wing2T = baseT - aWidth * pT_n * Tscale;
        wing2W = baseW - aWidth * pW_n * Wscale;

        % Draw filled arrowhead
        fill(handles.ax, [T2 wing1T wing2T], [W2 wing1W wing2W], color, ...
             'EdgeColor', color, 'LineWidth', 1, 'Tag', 'processLine', 'HandleVisibility', 'off');
    end

    function clearProcess(~, ~)
        clearProcessLine();
        resetProcessResults();
        updateStatus('Process line and results cleared.');
    end

    function clearProcessLine()
        handles = guidata(fig);
        % Remove process lines, arrowheads, and labels (use findall to include HandleVisibility off)
        delete(findall(handles.ax, 'Tag', 'processLine'));
        delete(findall(handles.ax, 'Tag', 'processLabel'));
        % Also remove SHR overlay from Tab 4 Send button
        delete(findall(handles.ax, 'Tag', 'shrOverlay'));
        delete(findall(handles.ax, 'Tag', 'shrOverlayLabel'));
        % Restore faded background elements
        restoreChartBackground();
    end

    function fadeChartBackground()
        % Fade isoline lines, labels, and comfort zone when a process is drawn
        handles = guidata(fig);
        fadeFactor = 0.4;  % how much to fade (0=invisible, 1=no change)

        % Fade chart lines
        chartLines = findobj(handles.ax, 'Tag', 'chartLine');
        for i = 1:length(chartLines)
            origColor = get(chartLines(i), 'Color');
            set(chartLines(i), 'UserData', origColor);
            fadedColor = 1 - fadeFactor * (1 - origColor);
            set(chartLines(i), 'Color', fadedColor);
        end

        % Fade chart labels
        chartLabels = findobj(handles.ax, 'Tag', 'chartLabel');
        for i = 1:length(chartLabels)
            origColor = get(chartLabels(i), 'Color');
            set(chartLabels(i), 'UserData', origColor);
            fadedColor = 1 - fadeFactor * (1 - origColor);
            set(chartLabels(i), 'Color', fadedColor);
        end

        % Fade comfort zone
        comfortObjs = findobj(handles.ax, 'Tag', 'comfortZone');
        for i = 1:length(comfortObjs)
            if isprop(comfortObjs(i), 'FaceAlpha')
                origAlpha = get(comfortObjs(i), 'FaceAlpha');
                set(comfortObjs(i), 'UserData', origAlpha);
                set(comfortObjs(i), 'FaceAlpha', origAlpha * fadeFactor);
            elseif isprop(comfortObjs(i), 'Color')
                origColor = get(comfortObjs(i), 'Color');
                set(comfortObjs(i), 'UserData', origColor);
                fadedColor = 1 - fadeFactor * (1 - origColor);
                set(comfortObjs(i), 'Color', fadedColor);
            end
        end
    end

    function restoreChartBackground()
        % Restore isoline lines, labels, and comfort zone to original colours
        handles = guidata(fig);

        % Restore chart lines
        chartLines = findobj(handles.ax, 'Tag', 'chartLine');
        for i = 1:length(chartLines)
            origColor = get(chartLines(i), 'UserData');
            if ~isempty(origColor)
                set(chartLines(i), 'Color', origColor);
            end
        end

        % Restore chart labels
        chartLabels = findobj(handles.ax, 'Tag', 'chartLabel');
        for i = 1:length(chartLabels)
            origColor = get(chartLabels(i), 'UserData');
            if ~isempty(origColor)
                set(chartLabels(i), 'Color', origColor);
            end
        end

        % Restore comfort zone
        comfortObjs = findobj(handles.ax, 'Tag', 'comfortZone');
        for i = 1:length(comfortObjs)
            origData = get(comfortObjs(i), 'UserData');
            if ~isempty(origData)
                if isprop(comfortObjs(i), 'FaceAlpha') && isscalar(origData)
                    set(comfortObjs(i), 'FaceAlpha', origData);
                elseif isprop(comfortObjs(i), 'Color')
                    set(comfortObjs(i), 'Color', origData);
                end
            end
        end
    end

    function resetProcessResults()
        handles = guidata(fig);
        fields = fieldnames(handles.procHandles);
        for i = 1:length(fields)
            set(handles.procHandles.(fields{i}), 'String', '---');
            set(handles.procHandles.(fields{i}), 'ForegroundColor', [0 0.3 0.6]);
        end
    end

    function exportData(~, ~)
        handles = guidata(fig);
        appData = getappdata(fig, 'appData');

        if isempty(appData.markedPoints)
            updateStatus('No marked points to export. Mark some points first.');
            return;
        end

        [filename, pathname] = uiputfile('*.csv', 'Export Data', 'psychrometric_points.csv');
        if filename == 0
            return;
        end

        filepath = fullfile(pathname, filename);

        fid = fopen(filepath, 'w');
        if appData.unitSystem == 2
            fprintf(fid, 'Point,Temperature_C,Humidity_Ratio_kg_kg,RH_percent,Wet_Bulb_C,Dew_Point_C,Enthalpy_kJ_kg,Specific_Volume_m3_kg\n');
        else
            fprintf(fid, 'Point,Temperature_F,Humidity_Ratio_lb_lb,RH_percent,Wet_Bulb_F,Dew_Point_F,Enthalpy_Btu_lb,Specific_Volume_ft3_lb\n');
        end

        for i = 1:length(appData.markedPoints)
            p = appData.markedPoints(i);
            fprintf(fid, 'P%d,%.2f,%.6f,%.3f,%.2f,%.2f,%.2f,%.4f\n', ...
                    i, p.T, p.W, p.RH*100, p.Twb, p.Tdp, p.h, p.v);
        end
        fclose(fid);

        updateStatus(sprintf('Data exported to %s', filename));
    end

    function saveChart(~, ~)
        handles = guidata(fig);

        [filename, pathname] = uiputfile({'*.png';'*.pdf';'*.fig'}, 'Save Chart', 'psychrometric_chart.png');
        if filename == 0
            return;
        end

        filepath = fullfile(pathname, filename);

        tempFig = figure('Visible', 'off', 'Position', [100 100 1000 700]);
        tempAx = copyobj(handles.ax, tempFig);
        set(tempAx, 'Position', [0.1 0.1 0.85 0.85]);

        if endsWith(filename, '.pdf')
            exportgraphics(tempAx, filepath, 'ContentType', 'vector');
        else
            exportgraphics(tempAx, filepath, 'Resolution', 300);
        end

        close(tempFig);
        updateStatus(sprintf('Chart saved to %s', filename));
    end

    function closeApp(~, ~)
        handles = guidata(fig);
        if isfield(handles, 'lsTimer') && ~isempty(handles.lsTimer) && isvalid(handles.lsTimer)
            stop(handles.lsTimer);
            delete(handles.lsTimer);
        end
        if isfield(handles, 'lsArduino') && ~isempty(handles.lsArduino)
            try clear handles.lsArduino; catch; end
        end
        delete(fig);
    end

    %% ==================== LIVE SENSOR CALLBACKS ====================

    function lsDetectPortCallback(~, ~)
        handles = guidata(fig);
        % Cross-platform port detection (Windows COMx, macOS /dev/cu.*, Linux /dev/tty*)
        ports = string.empty;
        try
            ports = serialportlist("available");
        catch
            % serialportlist needs R2019b+; fall back to nothing found
        end
        % Prefer USB ports (Arduino) on macOS / Linux
        usb = ports(contains(ports, ["usbmodem", "usbserial", "ttyACM", "ttyUSB"]));
        if ~isempty(usb)
            ports = usb;
        end
        if ~isempty(ports)
            set(handles.lsPortInput, 'String', char(ports(1)));
            updateStatus(sprintf('Port detected: %s', ports(1)));
        else
            updateStatus('No serial ports detected - plug in the Arduino and try again.');
        end
    end

    function lsConnectCallback(~, ~)
        handles = guidata(fig);
        btnState = get(handles.lsConnectBtn, 'Value');

        if btnState == 1
            % Connect
            try
                port = strtrim(get(handles.lsPortInput, 'String'));
                if isempty(port)
                    error('No serial port set - click Detect first.');
                end
                boardTypes = get(handles.lsBoardDropdown, 'String');
                boardIdx = get(handles.lsBoardDropdown, 'Value');
                board = boardTypes{boardIdx};

                updateStatus('Connecting to Arduino...');
                drawnow;

                a = arduino(port, board, 'Libraries', 'I2C');
                sensor = device(a, 'I2CAddress', '0x76');

                % Verify BME280 chip ID
                chipID = readRegister(sensor, 0xD0, 'uint8');
                if chipID ~= 0x60
                    error('Unexpected chip ID: 0x%02X (expected 0x60 for BME280)', chipID);
                end

                % Configure BME280: humidity oversampling x1
                writeRegister(sensor, 0xF2, 0x01, 'uint8');
                % Temp oversampling x1, pressure oversampling x1, normal mode
                writeRegister(sensor, 0xF4, 0x27, 'uint8');
                % Standby 1000ms, filter off
                writeRegister(sensor, 0xF5, 0xA0, 'uint8');

                handles.lsArduino = a;
                handles.lsSensor = sensor;

                % Read calibration data
                cal = bme280.readCalibration(sensor);
                setappdata(fig, 'lsCalibration', cal);

                % Get interval from dropdown
                intervals = [1 2 5 10];
                intervalIdx = get(handles.lsIntervalDropdown, 'Value');
                period = intervals(intervalIdx);

                % Create and start timer
                t = timer('ExecutionMode', 'fixedSpacing', ...
                          'Period', period, ...
                          'TimerFcn', @lsTimerCallback, ...
                          'ErrorFcn', @(~,~) updateStatus('Sensor read error.'));
                handles.lsTimer = t;

                set(handles.lsConnectBtn, 'String', 'Disconnect', ...
                    'BackgroundColor', [0.8 0.3 0.3]);
                set(handles.lsStatusText, 'String', 'Connected', ...
                    'ForegroundColor', [0.1 0.6 0.1]);

                guidata(fig, handles);
                start(t);
                updateStatus('BME280 sensor connected.');

            catch ME
                set(handles.lsConnectBtn, 'Value', 0, 'String', 'Connect', ...
                    'BackgroundColor', [0.3 0.7 0.3]);
                set(handles.lsStatusText, 'String', 'Disconnected', ...
                    'ForegroundColor', [0.8 0.1 0.1]);
                handles.lsArduino = [];
                handles.lsSensor = [];
                handles.lsTimer = [];
                guidata(fig, handles);
                updateStatus(['Connection failed: ' ME.message]);
            end
        else
            % Disconnect
            if ~isempty(handles.lsTimer) && isvalid(handles.lsTimer)
                stop(handles.lsTimer);
                delete(handles.lsTimer);
            end
            handles.lsTimer = [];

            if ~isempty(handles.lsArduino)
                try clear handles.lsArduino; catch; end
            end
            handles.lsArduino = [];
            handles.lsSensor = [];

            % Remove live marker from chart
            existingMarker = getappdata(fig, 'lsSensorMarkerHandle');
            if ~isempty(existingMarker) && isvalid(existingMarker)
                delete(existingMarker);
            end
            setappdata(fig, 'lsSensorMarkerHandle', []);
            delete(findobj(handles.ax, 'Tag', 'lsSensorDiamond'));

            set(handles.lsConnectBtn, 'String', 'Connect', ...
                'BackgroundColor', [0.3 0.7 0.3]);
            set(handles.lsStatusText, 'String', 'Disconnected', ...
                'ForegroundColor', [0.8 0.1 0.1]);
            guidata(fig, handles);
            updateStatus('Sensor disconnected.');
        end
    end

    function lsTimerCallback(~, ~)
        handles = guidata(fig);
        sensor = handles.lsSensor;
        if isempty(sensor)
            return;
        end

        try
            % Read 8 raw bytes from registers 0xF7-0xFE
            rawBytes = zeros(1, 8, 'uint8');
            for k = 0:7
                rawBytes(k+1) = readRegister(sensor, uint8(0xF7 + k), 'uint8');
            end

            % Get calibration data
            cal = getappdata(fig, 'lsCalibration');

            % Compensate BME280 readings
            [T_C, RH_pct, P_kPa] = bme280.compensate(rawBytes, cal);

            % Get current unit system
            appData = getappdata(fig, 'appData');
            unitSys = appData.unitSystem;
            P_atm = appData.pressure;  % Pa

            % Compute W in SI for storage
            Pws_si = psychro.saturationPressure(T_C, 2);
            Pw_si = (RH_pct / 100) * Pws_si;
            W_si = psychro.humidityRatio(Pw_si, P_atm, 2);

            % Store live data for Use as State A/B buttons
            if unitSys == 1
                liveData.T = T_C * 9/5 + 32;
                liveData.W = W_si;  % keep W in base units
            else
                liveData.T = T_C;
                liveData.W = W_si;
            end
            setappdata(fig, 'lsLiveData', liveData);

            % Convert temperature for display if IP
            if unitSys == 1
                T_display = T_C * 9/5 + 32;
                tempUnit = 'degF';
            else
                T_display = T_C;
                tempUnit = 'degC';
            end

            % Compute psychrometric properties using SI internally
            Pws = psychro.saturationPressure(T_C, 2);  % Always compute in SI
            Pw = (RH_pct / 100) * Pws;
            W = psychro.humidityRatio(Pw, P_atm, 2);

            % Dew point: find Tdp where saturationPressure(Tdp) = Pw
            if Pw > 0
                Tdp = psychro.dewPointFromPw(Pw);
            else
                Tdp = -273.15;
            end

            % Wet-bulb: iterative approximation
            Twb = psychro.wetBulbFromTW(T_C, W, P_atm);

            % Enthalpy (SI): h = 1.006*T + W*(2501 + 1.86*T) kJ/kg
            h_SI = 1.006 * T_C + W * (2501 + 1.86 * T_C);

            % Specific volume (SI): v = 0.287042*(T+273.15)*(1+1.6078*W)/(P_atm/1000)
            v_SI = 0.287042 * (T_C + 273.15) * (1 + 1.6078 * W) / (P_atm / 1000);

            % Update displays
            if unitSys == 1
                Tdp_display = Tdp * 9/5 + 32;
                Twb_display = Twb * 9/5 + 32;
                W_display = W * 7000;  % grains/lb
                h_display = h_SI * 0.43;  % BTU/lb approx
                v_display = v_SI * 16.018;  % ft3/lb approx
                set(handles.lsTempDisplay, 'String', sprintf('%.1f %s', T_display, tempUnit));
                set(handles.lsRHDisplay, 'String', sprintf('%.1f %%', RH_pct));
                set(handles.lsPressDisplay, 'String', sprintf('%.1f inHg', P_kPa * 0.2953));
                set(handles.lsWDisplay, 'String', sprintf('%.1f gr/lb', W_display));
                set(handles.lsTwbDisplay, 'String', sprintf('%.1f degF', Twb_display));
                set(handles.lsTdpDisplay, 'String', sprintf('%.1f degF', Tdp_display));
                set(handles.lsEnthalpyDisplay, 'String', sprintf('%.2f BTU/lb', h_display));
                set(handles.lsVolumeDisplay, 'String', sprintf('%.3f ft3/lb', v_display));
            else
                set(handles.lsTempDisplay, 'String', sprintf('%.1f %s', T_display, tempUnit));
                set(handles.lsRHDisplay, 'String', sprintf('%.1f %%', RH_pct));
                set(handles.lsPressDisplay, 'String', sprintf('%.1f Pa', P_kPa * 1000));
                set(handles.lsWDisplay, 'String', sprintf('%.4f kg/kg', W));
                set(handles.lsTwbDisplay, 'String', sprintf('%.1f degC', Twb));
                set(handles.lsTdpDisplay, 'String', sprintf('%.1f degC', Tdp));
                set(handles.lsEnthalpyDisplay, 'String', sprintf('%.2f kJ/kg', h_SI));
                set(handles.lsVolumeDisplay, 'String', sprintf('%.4f m3/kg', v_SI));
            end

            % Comfort assessment using actual ASHRAE 55 comfort zone parameters
            cloVal = appData.comfortClo;
            metVal = appData.comfortMet;
            airVel = appData.comfortAirVel;
            [T_lo, T_hi] = psychro.getComfortTempRange(cloVal, metVal, airVel, 2);  % always SI
            W_upper = 0.012;  % ASHRAE 55 upper humidity limit
            RH_lo = 0.30;
            inComfort = (T_C >= T_lo && T_C <= T_hi && W_si <= W_upper && RH_pct/100 >= RH_lo);
            if inComfort
                set(handles.lsComfortText, 'String', 'COMFORTABLE', ...
                    'ForegroundColor', [0.1 0.6 0.1]);
            else
                set(handles.lsComfortText, 'String', 'OUTSIDE COMFORT', ...
                    'ForegroundColor', [0.8 0.1 0.1]);
            end

            % Plot on chart if checked
            if get(handles.lsPlotOnChart, 'Value') == 1
                % Use chart coordinates: T on x-axis, W on y-axis (in display units)
                if unitSys == 1
                    chartT = T_display;
                    chartW = W * 7000;  % grains/lb for IP chart
                else
                    chartT = T_display;
                    chartW = W;  % kg/kg — matches chart y-axis
                end

                % Use appdata for marker handle to persist across timer ticks
                existingMarker = getappdata(fig, 'lsSensorMarkerHandle');
                hold(handles.ax, 'on');
                if ~isempty(existingMarker) && isvalid(existingMarker)
                    set(existingMarker, 'XData', chartT, 'YData', chartW);
                else
                    % Delete any stale sensor markers first
                    delete(findobj(handles.ax, 'Tag', 'lsSensorDiamond'));
                    newMarker = plot(handles.ax, chartT, chartW, ...
                        'rd', 'MarkerSize', 5, 'LineWidth', 1, ...
                        'MarkerFaceColor', [1 0 0], ...
                        'HandleVisibility', 'off', 'HitTest', 'off', ...
                        'Tag', 'lsSensorDiamond');
                    setappdata(fig, 'lsSensorMarkerHandle', newMarker);
                end
                hold(handles.ax, 'off');

                % If Process Analysis has Live Sensor selected, refresh it
                lsRefreshProcessIfLive();
            end

            % If Heat Load outdoor/indoor source is "Live Sensor Data", update fields
            outItems = get(handles.hlOutdoorSource, 'String');
            outVal = get(handles.hlOutdoorSource, 'Value');
            if strcmp(outItems{outVal}, 'Live Sensor Data')
                if unitSys == 1
                    set(handles.hlOutdoorTemp, 'String', sprintf('%.1f', T_C * 9/5 + 32));
                else
                    set(handles.hlOutdoorTemp, 'String', sprintf('%.1f', T_C));
                end
                set(handles.hlOutdoorRH, 'String', sprintf('%.1f', RH_pct));
            end
            inItems = get(handles.hlIndoorSource, 'String');
            inVal = get(handles.hlIndoorSource, 'Value');
            if strcmp(inItems{inVal}, 'Live Sensor Data')
                if unitSys == 1
                    set(handles.hlIndoorTemp, 'String', sprintf('%.1f', T_C * 9/5 + 32));
                else
                    set(handles.hlIndoorTemp, 'String', sprintf('%.1f', T_C));
                end
                set(handles.hlIndoorRH, 'String', sprintf('%.1f', RH_pct));
            end

            % Log data if active
            if get(handles.lsLogBtn, 'Value') == 1
                timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
                newRow = {timestamp, T_C, RH_pct, P_kPa*1000, W, Twb, Tdp, h_SI, v_SI};
                handles.lsLogData{end+1} = newRow;
                set(handles.lsLogCount, 'String', ...
                    sprintf('Logged points: %d', numel(handles.lsLogData)));
            end

            guidata(fig, handles);

        catch ME
            updateStatus(['Sensor read error: ' ME.message]);
        end
    end

    function lsLogCallback(~, ~)
        handles = guidata(fig);
        if get(handles.lsLogBtn, 'Value') == 1
            set(handles.lsLogBtn, 'String', 'Stop Logging', ...
                'BackgroundColor', [0.8 0.3 0.3], ...
                'ForegroundColor', [1 1 1]);
            updateStatus('Data logging started.');
        else
            set(handles.lsLogBtn, 'String', 'Log Data', ...
                'BackgroundColor', [0.85 0.85 0.85], ...
                'ForegroundColor', [0 0 0]);
            updateStatus('Data logging stopped.');
        end
    end

    function lsExportCallback(~, ~)
        handles = guidata(fig);
        if isempty(handles.lsLogData)
            updateStatus('No logged data to export.');
            return;
        end

        [fileName, pathName] = uiputfile('*.csv', 'Export Sensor Log', 'sensor_log.csv');
        if isequal(fileName, 0)
            return;
        end

        fid = fopen(fullfile(pathName, fileName), 'w');
        fprintf(fid, 'Timestamp,Temperature_C,RH_pct,Pressure_Pa,HumidityRatio_kgkg,WetBulb_C,DewPoint_C,Enthalpy_kJkg,SpecificVolume_m3kg\n');
        for i = 1:numel(handles.lsLogData)
            row = handles.lsLogData{i};
            fprintf(fid, '%s,%.2f,%.2f,%.1f,%.6f,%.2f,%.2f,%.4f,%.6f\n', ...
                row{1}, row{2}, row{3}, row{4}, row{5}, row{6}, row{7}, row{8}, row{9});
        end
        fclose(fid);
        updateStatus(sprintf('Exported %d points to %s', numel(handles.lsLogData), fileName));
    end

    function lsClearLogCallback(~, ~)
        handles = guidata(fig);
        handles.lsLogData = {};
        set(handles.lsLogCount, 'String', 'Logged points: 0');
        guidata(fig, handles);
        updateStatus('Log cleared.');
    end

    function lsIntervalCallback(~, ~)
        handles = guidata(fig);
        intervals = [1 2 5 10];
        intervalIdx = get(handles.lsIntervalDropdown, 'Value');
        newPeriod = intervals(intervalIdx);

        if ~isempty(handles.lsTimer) && isvalid(handles.lsTimer)
            wasRunning = strcmp(get(handles.lsTimer, 'Running'), 'on');
            if wasRunning
                stop(handles.lsTimer);
            end
            set(handles.lsTimer, 'Period', newPeriod);
            if wasRunning
                start(handles.lsTimer);
            end
        end
        updateStatus(sprintf('Update interval set to %d seconds.', newPeriod));
    end

    %% ==================== BME280 HELPER FUNCTIONS ====================

    %% ==================== HELPER FUNCTIONS ====================

    function result = ternary(cond, trueVal, falseVal)
        if cond
            result = trueVal;
        else
            result = falseVal;
        end
    end

    function drawChart(figHandle)
        handles = guidata(figHandle);
        appData = getappdata(figHandle, 'appData');

        % Delete ALL children including those with HandleVisibility off
        delete(findall(handles.ax, 'Type', 'line'));
        delete(findall(handles.ax, 'Type', 'text'));
        delete(findall(handles.ax, 'Type', 'patch'));
        cla(handles.ax);
        hold(handles.ax, 'on');
        grid(handles.ax, 'on');
        box(handles.ax, 'on');

        TRange = appData.TRange;
        P = appData.pressure;
        unitSystem = appData.unitSystem;

        % Plot saturation curve
        T = linspace(TRange(1), TRange(2), 200);
        W_sat = zeros(size(T));
        for i = 1:length(T)
            Pws = psychro.saturationPressure(T(i), unitSystem);
            W_sat(i) = psychro.humidityRatio(Pws, P, unitSystem);
        end
        hSat = plot(handles.ax, T, W_sat, 'b-', 'LineWidth', 2.5, 'Tag', 'chartLine');

        % Plot RH lines
        RH_values = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9];
        T = linspace(TRange(1), TRange(2), 100);
        hRH = [];
        for RH = RH_values
            W = zeros(size(T));
            for i = 1:length(T)
                Pws = psychro.saturationPressure(T(i), unitSystem);
                Pw = RH * Pws;
                W(i) = psychro.humidityRatio(Pw, P, unitSystem);
            end
            hLine = plot(handles.ax, T, W, '-', 'Color', [0.65 0.65 0.65], 'LineWidth', 0.5, 'Tag', 'chartLine');
            if isempty(hRH), hRH = hLine; end

            idx = round(0.85 * length(T));
            if W(idx) > 0 && W(idx) < 0.03
                text(handles.ax, T(idx), W(idx), sprintf('%d%%', round(RH*100)), ...
                    'FontSize', 7, 'Color', [0.45 0.45 0.45], 'Tag', 'chartLabel');
            end
        end

        % Plot wet-bulb lines
        if unitSystem == 1
            Twb_values = TRange(1):10:TRange(2);
        else
            Twb_values = TRange(1):5:TRange(2);
        end
        hWb = [];
        wbIdx = 0;
        for Twb = Twb_values
            if Twb < TRange(1), continue; end
            wbIdx = wbIdx + 1;
            T = linspace(Twb, TRange(2), 100);
            W = zeros(size(T));
            for i = 1:length(T)
                W(i) = psychro.humidityRatioFromWetBulb(T(i), Twb, P, unitSystem);
            end
            valid = W > 0 & W < 0.03;
            if sum(valid) > 2
                hLine = plot(handles.ax, T(valid), W(valid), '-', 'Color', [0.6 0.8 0.6], 'LineWidth', 0.4, 'Tag', 'chartLine');
                if isempty(hWb), hWb = hLine; end
                % Label every other line
                if mod(wbIdx, 2) == 1
                    validIdx = find(valid, 1, 'first');
                    if ~isempty(validIdx) && W(validIdx) > 0.001 && W(validIdx) < 0.029
                        if unitSystem == 1
                            lbl = sprintf('%g°F', Twb);
                        else
                            lbl = sprintf('%g°C', Twb);
                        end
                        text(handles.ax, T(validIdx), W(validIdx), lbl, ...
                            'FontSize', 6, 'Color', [0.4 0.65 0.4], 'Rotation', -30, 'Tag', 'chartLabel');
                    end
                end
            end
        end

        % Plot enthalpy lines
        if unitSystem == 1
            h_values = 10:5:60;
        else
            h_values = 20:10:150;
        end
        hEnth = [];
        enthIdx = 0;
        for h = h_values
            enthIdx = enthIdx + 1;
            T = linspace(TRange(1), TRange(2), 100);
            W = zeros(size(T));
            for i = 1:length(T)
                W(i) = psychro.humidityRatioFromEnthalpy(h, T(i), unitSystem);
            end
            valid = W > 0 & W < 0.03 & ~isnan(W);
            if sum(valid) > 2
                hLine = plot(handles.ax, T(valid), W(valid), '--', 'Color', [0.85 0.6 0.6], 'LineWidth', 0.4, 'Tag', 'chartLine');
                if isempty(hEnth), hEnth = hLine; end
                % Label every other line
                if mod(enthIdx, 2) == 1
                    validIdx = find(valid, 1, 'first');
                    if ~isempty(validIdx) && W(validIdx) > 0.001 && W(validIdx) < 0.029
                        if unitSystem == 1
                            lbl = sprintf('%g Btu/lb', h);
                        else
                            lbl = sprintf('%g kJ/kg', h);
                        end
                        text(handles.ax, T(validIdx), W(validIdx), lbl, ...
                            'FontSize', 6, 'Color', [0.7 0.45 0.45], 'Rotation', -45, 'Tag', 'chartLabel');
                    end
                end
            end
        end

        % Plot specific volume lines
        if unitSystem == 1
            v_values = 12.5:0.5:15.5;  % ft^3/lb
        else
            v_values = 0.78:0.02:0.98;  % m^3/kg
        end
        hVol = [];
        volIdx = 0;
        for v = v_values
            volIdx = volIdx + 1;
            T = linspace(TRange(1), TRange(2), 100);
            W = zeros(size(T));
            for i = 1:length(T)
                W(i) = psychro.humidityRatioFromVolume(v, T(i), P, unitSystem);
            end
            valid = W > 0 & W < 0.03 & ~isnan(W);
            if sum(valid) > 2
                hLine = plot(handles.ax, T(valid), W(valid), ':', 'Color', [0.75 0.6 0.85], 'LineWidth', 0.4, 'Tag', 'chartLine');
                if isempty(hVol), hVol = hLine; end
                % Label every other line
                if mod(volIdx, 2) == 1
                    validIdx = find(valid, 1, 'first');
                    if ~isempty(validIdx) && W(validIdx) > 0.001 && W(validIdx) < 0.029
                        if unitSystem == 1
                            lbl = sprintf('%g ft^3/lb', v);
                        else
                            lbl = sprintf('%g m^3/kg', v);
                        end
                        text(handles.ax, T(validIdx), W(validIdx), lbl, ...
                            'FontSize', 6, 'Color', [0.6 0.45 0.7], 'Rotation', 80, 'Tag', 'chartLabel');
                    end
                end
            end
        end

        % Plot ASHRAE 55 comfort zone
        hComfort = [];
        if appData.showComfortZone
            hComfort = plotComfortZone(handles.ax, P, unitSystem, ...
                appData.comfortClo, appData.comfortMet, appData.comfortAirVel);
        end

        % Set labels
        if unitSystem == 1
            xlabel(handles.ax, 'Dry Bulb Temperature (°F)', 'FontSize', 10, 'FontWeight', 'bold');
            ylabel(handles.ax, 'Humidity Ratio (lb_w/lb_{da})', 'FontSize', 10, 'FontWeight', 'bold');
            title(handles.ax, sprintf('Interactive Psychrometric Chart (P = %.3f psi)', P), ...
                  'FontSize', 12, 'FontWeight', 'bold');
        else
            xlabel(handles.ax, 'Dry Bulb Temperature (°C)', 'FontSize', 10, 'FontWeight', 'bold');
            ylabel(handles.ax, 'Humidity Ratio (kg_w/kg_{da})', 'FontSize', 10, 'FontWeight', 'bold');
            title(handles.ax, sprintf('Interactive Psychrometric Chart (P = %.0f Pa)', P), ...
                  'FontSize', 12, 'FontWeight', 'bold');
        end

        xlim(handles.ax, TRange);
        ylim(handles.ax, [0 0.03]);

        % Add legend using explicit handles
        legendHandles = hSat;
        legendLabels = {'Saturation (100% RH)'};
        if ~isempty(hRH)
            legendHandles(end+1) = hRH;
            legendLabels{end+1} = 'Relative Humidity';
        end
        if ~isempty(hWb)
            legendHandles(end+1) = hWb;
            legendLabels{end+1} = 'Wet-Bulb Temp';
        end
        if ~isempty(hEnth)
            legendHandles(end+1) = hEnth;
            legendLabels{end+1} = 'Enthalpy';
        end
        if ~isempty(hVol)
            legendHandles(end+1) = hVol;
            legendLabels{end+1} = 'Specific Volume';
        end
        if ~isempty(hComfort)
            legendHandles(end+1) = hComfort;
            legendLabels{end+1} = 'ASHRAE 55 Comfort';
        end
        legend(handles.ax, legendHandles, legendLabels, ...
               'Location', 'northwest', 'FontSize', 7);

        % Replot any existing marked points
        if ~isempty(appData.markedPoints)
            colors = [1 0 0; 0 0.5 0; 0 0 1; 0.8 0.4 0; 0.5 0 0.5; 0 0.7 0.7; 0.8 0 0.4; 0.4 0.4 0; 0 0.4 0.8; 0.6 0.2 0];
            handles.markerHandles = [];
            for mi = 1:length(appData.markedPoints)
                p = appData.markedPoints(mi);
                colorIdx = mod(mi - 1, size(colors, 1)) + 1;
                ptColor = colors(colorIdx, :);
                hm = plot(handles.ax, p.T, p.W, ...
                     'o', 'MarkerSize', 6, 'MarkerFaceColor', ptColor, ...
                     'MarkerEdgeColor', ptColor, 'LineWidth', 1.5, ...
                     'HandleVisibility', 'off', 'Tag', 'markedPoint');
                text(handles.ax, p.T + 0.5, p.W + 0.0005, ...
                     sprintf('P%d', mi), 'FontSize', 9, 'FontWeight', 'bold', ...
                     'Color', ptColor, 'Tag', 'markedLabel');
                handles.markerHandles(end+1) = hm;
            end
            guidata(figHandle, handles);
        end

        hold(handles.ax, 'off');

        % Re-enable click callback
        set(handles.ax, 'ButtonDownFcn', @chartClick);

        % Make all children clickable through to axes
        ch = get(handles.ax, 'Children');
        set(ch, 'HitTest', 'off');
    end

    function displayProperties(props, unitSystem)
        handles = guidata(fig);

        RH_pct = props.RH * 100;
        if RH_pct < 1
            rhStr = sprintf('%.3f %%', RH_pct);
        elseif RH_pct < 10
            rhStr = sprintf('%.2f %%', RH_pct);
        else
            rhStr = sprintf('%.1f %%', RH_pct);
        end

        if unitSystem == 2
            set(handles.propHandles.T_db, 'String', sprintf('%.2f C', props.T));
            set(handles.propHandles.W, 'String', sprintf('%.5f kg/kg', props.W));
            set(handles.propHandles.RH, 'String', rhStr);
            set(handles.propHandles.T_wb, 'String', sprintf('%.2f C', props.Twb));
            set(handles.propHandles.T_dp, 'String', sprintf('%.2f C', props.Tdp));
            set(handles.propHandles.h, 'String', sprintf('%.2f kJ/kg', props.h));
            set(handles.propHandles.v, 'String', sprintf('%.4f m3/kg', props.v));
            set(handles.propHandles.P_v, 'String', sprintf('%.1f Pa', props.Pv));
            set(handles.propHandles.P_ws, 'String', sprintf('%.1f Pa', props.Pws));
        else
            set(handles.propHandles.T_db, 'String', sprintf('%.2f F', props.T));
            set(handles.propHandles.W, 'String', sprintf('%.5f lb/lb', props.W));
            set(handles.propHandles.RH, 'String', rhStr);
            set(handles.propHandles.T_wb, 'String', sprintf('%.2f F', props.Twb));
            set(handles.propHandles.T_dp, 'String', sprintf('%.2f F', props.Tdp));
            set(handles.propHandles.h, 'String', sprintf('%.2f Btu/lb', props.h));
            set(handles.propHandles.v, 'String', sprintf('%.4f ft3/lb', props.v));
            set(handles.propHandles.P_v, 'String', sprintf('%.4f psi', props.Pv));
            set(handles.propHandles.P_ws, 'String', sprintf('%.4f psi', props.Pws));
        end
    end

    function resetProperties()
        handles = guidata(fig);
        fields = fieldnames(handles.propHandles);
        for i = 1:length(fields)
            set(handles.propHandles.(fields{i}), 'String', '---');
        end
        handles.currentPoint = [];
        guidata(fig, handles);
    end

    function updateCurrentMarker(T, W)
        handles = guidata(fig);

        % Delete previous current marker if it exists
        if isfield(handles, 'currentMarkerHandle') && ~isempty(handles.currentMarkerHandle) && isvalid(handles.currentMarkerHandle)
            delete(handles.currentMarkerHandle);
        end
        % Also clean up any stale tagged markers
        oldMarkers = findobj(handles.ax, 'Tag', 'currentMarker');
        if ~isempty(oldMarkers)
            delete(oldMarkers);
        end

        hold(handles.ax, 'on');
        handles.currentMarkerHandle = plot(handles.ax, T, W, 'ko', ...
             'MarkerSize', 7, 'MarkerFaceColor', [0.2 0.2 0.2], ...
             'LineWidth', 1.5, 'Tag', 'currentMarker', ...
             'HandleVisibility', 'off', 'HitTest', 'off', 'PickableParts', 'none');
        hold(handles.ax, 'off');
        guidata(fig, handles);

        % Ensure all children pass clicks through to axes
        ch = get(handles.ax, 'Children');
        set(ch, 'HitTest', 'off');
        set(handles.ax, 'ButtonDownFcn', @chartClick);
    end

    function updateStatus(msg)
        handles = guidata(fig);
        set(handles.statusText, 'String', msg);
    end

    %% ==================== PSYCHROMETRIC EQUATIONS ====================

    function hPatch = plotComfortZone(ax, P, unitSystem, cloVal, metVal, airVel)
        % Plot ASHRAE Standard 55 thermal comfort zone
        % Zone boundaries shift based on clothing (clo), metabolic rate (met),
        % and air velocity per the graphic comfort zone method.
        %
        % Reference boundaries (ASHRAE 55-2023):
        %   0.5 clo (summer): 23.0 - 26.5 C  (73.5 - 80 F)
        %   1.0 clo (winter): 20.0 - 24.0 C  (68 - 75.5 F)
        %   Upper humidity limit: W = 0.012 kg/kg
        %   Applicable for 1.0-1.3 met, still air (< 0.2 m/s)
        %
        % Adjustments:
        %   Clo: linear interpolation/extrapolation from reference points
        %   Met: each +0.1 met above 1.1 shifts zone ~0.8 C cooler
        %   Air velocity: each +0.3 m/s above 0.1 shifts zone ~1.0 C warmer

        % Get temperature range for current parameters
        [T_lo, T_hi] = psychro.getComfortTempRange(cloVal, metVal, airVel, unitSystem);

        % RH bounds for the comfort zone
        RH_lo = 0.30;
        RH_hi = 0.60;
        W_upper_limit = 0.012;

        % Build polygon: trace bottom (low RH) left-to-right,
        % then top (high RH) right-to-left
        nPts = 30;

        T_bot = linspace(T_lo, T_hi, nPts);
        W_bot = zeros(size(T_bot));
        for i = 1:nPts
            Pws = psychro.saturationPressure(T_bot(i), unitSystem);
            W_bot(i) = psychro.humidityRatio(RH_lo * Pws, P, unitSystem);
        end

        T_top = linspace(T_hi, T_lo, nPts);
        W_top = zeros(size(T_top));
        for i = 1:nPts
            Pws = psychro.saturationPressure(T_top(i), unitSystem);
            W_top(i) = min(psychro.humidityRatio(RH_hi * Pws, P, unitSystem), W_upper_limit);
        end

        T_poly = [T_bot T_top];
        W_poly = [W_bot W_top];

        % Choose colour based on clo value (blue=cold/winter, orange=warm/summer)
        % Interpolate between summer orange and winter blue
        t = max(0, min(1, (cloVal - 0.3) / (1.5 - 0.3)));
        faceColour = (1 - t) * [1.0 0.88 0.72] + t * [0.72 0.85 1.0];
        edgeColour = (1 - t) * [0.8 0.5 0.2] + t * [0.3 0.5 0.8];
        labelColour = (1 - t) * [0.7 0.4 0.1] + t * [0.2 0.4 0.7];

        % Draw the comfort zone
        hPatch = fill(ax, T_poly, W_poly, faceColour, ...
             'FaceAlpha', 0.15, 'EdgeColor', edgeColour, ...
             'LineWidth', 1.0, 'LineStyle', '--', ...
             'HitTest', 'off', 'PickableParts', 'none', ...
             'Tag', 'comfortZone');

        % Label at the bottom edge of the zone
        midT = (T_lo + T_hi) / 2;
        % Place labels near the bottom of the zone
        Pws_lo = psychro.saturationPressure(T_lo, unitSystem);
        W_bottom = psychro.humidityRatio(RH_lo * Pws_lo, P, unitSystem);

        text(ax, midT, W_bottom + 0.0005, ...
             sprintf('Comfort Zone  %.1f clo, %.1f met', cloVal, metVal), ...
             'FontSize', 6, 'FontWeight', 'bold', ...
             'Color', labelColour, 'HorizontalAlignment', 'center', ...
             'HitTest', 'off', 'PickableParts', 'none', 'Tag', 'comfortZone');

        % Temperature range annotation
        if unitSystem == 2
            rangeStr = sprintf('%.1f - %.1f C', T_lo, T_hi);
        else
            rangeStr = sprintf('%.1f - %.1f F', T_lo, T_hi);
        end
        text(ax, midT, W_bottom - 0.0003, rangeStr, ...
             'FontSize', 6, 'Color', labelColour, ...
             'HorizontalAlignment', 'center', ...
             'HitTest', 'off', 'PickableParts', 'none', 'Tag', 'comfortZone');
    end

end
