function [T_lo, T_hi] = getComfortTempRange(cloVal, metVal, airVel, unitSystem)
    % GETCOMFORTTEMPRANGE Approximate ASHRAE 55 comfort-zone operative temperature range for given clo, met and air speed.
    %   Part of the 'psychro' package - call as psychro.getComfortTempRange(...).
    %
    % Calculate comfort zone operative temperature range
    % based on clothing, metabolic rate, and air velocity.
    %
    % Reference points (ASHRAE 55, SI):
    %   0.5 clo: 23.0 - 26.5 C
    %   1.0 clo: 20.0 - 24.0 C
    % Linear interpolation/extrapolation for other clo values.
    % Met adjustment: -0.8 C per +0.1 met above 1.1
    % Air velocity adjustment: +1.0 C per +0.3 m/s above 0.1

    % Base ranges at reference clo values (in Celsius)
    T_lo_05 = 23.0;  T_hi_05 = 26.5;   % 0.5 clo
    T_lo_10 = 20.0;  T_hi_10 = 24.0;   % 1.0 clo

    % Interpolate/extrapolate for clo
    % Slope: per 0.5 clo increase, temps drop by ~3 C
    slope_lo = (T_lo_10 - T_lo_05) / (1.0 - 0.5);  % -6 C/clo
    slope_hi = (T_hi_10 - T_hi_05) / (1.0 - 0.5);  % -5 C/clo

    T_lo = T_lo_05 + slope_lo * (cloVal - 0.5);
    T_hi = T_hi_05 + slope_hi * (cloVal - 0.5);

    % Metabolic rate adjustment (reference = 1.1 met)
    met_shift = -0.8 * (metVal - 1.1) / 0.1;  % C per 0.1 met
    T_lo = T_lo + met_shift;
    T_hi = T_hi + met_shift;

    % Air velocity adjustment (reference = 0.1 m/s)
    vel_shift = 1.0 * (airVel - 0.1) / 0.3;   % C per 0.3 m/s
    T_lo = T_lo + vel_shift;
    T_hi = T_hi + vel_shift;

    % Convert to IP if needed
    if unitSystem == 1
        T_lo = T_lo * 9/5 + 32;
        T_hi = T_hi * 9/5 + 32;
    end
end
