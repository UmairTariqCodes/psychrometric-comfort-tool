function W = humidityRatioFromVolume(v, T, P, unitSystem)
    % HUMIDITYRATIOFROMVOLUME Humidity ratio from specific volume v and dry-bulb temperature T.
    %   Part of the 'psychro' package - call as psychro.humidityRatioFromVolume(...).
    %
    % Calculate humidity ratio from specific volume and temperature
    % v = (Ra * T_abs / P) * (1 + 1.6078 * W)
    if unitSystem == 1  % IP units
        T_R = T + 459.67;       % Rankine
        P_psf = P * 144;        % psf
        Ra = 53.352;            % ft*lbf/(lb*R)
        W = (v * P_psf / (Ra * T_R) - 1) / 1.6078;
    else  % SI units
        T_K = T + 273.15;       % Kelvin
        Ra = 287.055;           % J/(kg*K)
        W = (v * P / (Ra * T_K) - 1) / 1.6078;
    end
    W = max(0, min(W, 0.03));
end
