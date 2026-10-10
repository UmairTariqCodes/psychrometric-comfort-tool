function [T_adp, W_adp] = findADP(T_room, W_room, SHR, P, unitSys)
    % FINDADP Apparatus dew point: intersection of the room SHR line with the saturation curve.
    %   Part of the 'psychro' package - call as psychro.findADP(...).
    %
    % Find Apparatus Dew Point: where the SHR line from room condition
    % intersects the saturation curve.
    %
    % SHR line slope on psychrometric chart (T vs W):
    %   dW/dT = (1 - SHR) * Cp / (SHR * hfg)
    % For cooling, we walk T downward from T_room until W_line(T) >= W_sat(T)

    if unitSys == 2  % SI
        Cp = 1006;       % J/(kg·K)
        hfg = 2501000;   % J/kg
    else  % IP
        Cp = 0.24;       % Btu/(lb·°F)
        hfg = 1061;      % Btu/lb
    end

    if SHR >= 1.0 || SHR <= 0
        % Pure sensible or invalid SHR — no ADP intersection
        T_adp = NaN;
        W_adp = NaN;
        return;
    end

    slope = (1 - SHR) * Cp / (SHR * hfg);  % dW/dT (positive value)
    % For cooling: T decreases, W decreases, so W_line = W_room + slope*(T - T_room)
    % Since T < T_room, dT is negative, and slope > 0, so W_line < W_room ✓

    % Bisection: find T where W_line(T) = W_sat(T)
    % At T_room: W_line = W_room > W_sat(T_room) if RH < 100% (above sat? no, below sat)
    % Actually W_room < W_sat(T_room) always (point is below saturation)
    % As T decreases: W_line decreases linearly, W_sat decreases exponentially
    % At some T_adp: W_line = W_sat → intersection

    T_low = -10;  % lower bound
    if unitSys == 1
        T_low = 10;  % °F lower bound
    end
    T_high = T_room;

    % Check: at T_room, f = W_line - W_sat should be negative (W_room < W_sat)
    Pws_room = psychro.saturationPressure(T_room, unitSys);
    W_sat_room = psychro.humidityRatio(Pws_room, P, unitSys);
    f_high = W_room - W_sat_room;  % should be negative (below saturation)

    % At T_low, check if line is above saturation
    W_line_low = W_room + slope * (T_low - T_room);
    Pws_low = psychro.saturationPressure(T_low, unitSys);
    W_sat_low = psychro.humidityRatio(Pws_low, P, unitSys);
    f_low = W_line_low - W_sat_low;

    if f_low < 0
        % SHR line never reaches saturation curve in valid range
        T_adp = NaN;
        W_adp = NaN;
        return;
    end

    % Bisect to find crossing
    for iter = 1:100
        T_mid = (T_low + T_high) / 2;
        W_line_mid = W_room + slope * (T_mid - T_room);
        Pws_mid = psychro.saturationPressure(T_mid, unitSys);
        W_sat_mid = psychro.humidityRatio(Pws_mid, P, unitSys);
        f_mid = W_line_mid - W_sat_mid;

        if abs(f_mid) < 1e-7 || (T_high - T_low) < 0.01
            break;
        end

        if f_mid > 0
            T_low = T_mid;  % line still above sat, move right
        else
            T_high = T_mid;  % line below sat, move left
        end
    end

    T_adp = T_mid;
    Pws_adp = psychro.saturationPressure(T_adp, unitSys);
    W_adp = psychro.humidityRatio(Pws_adp, P, unitSys);  % ADP is ON saturation curve
end
