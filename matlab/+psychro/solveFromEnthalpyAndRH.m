function [T, W] = solveFromEnthalpyAndRH(h, RH, P, unitSystem)
    % SOLVEFROMENTHALPYANDRH State point (T, W) from enthalpy and relative humidity.
    %   Part of the 'psychro' package - call as psychro.solveFromEnthalpyAndRH(...).
    if unitSystem == 1
        T_low = 0; T_high = 150;
    else
        T_low = -10; T_high = 60;
    end

    for iter = 1:100
        T_mid = (T_low + T_high) / 2;
        Pws = psychro.saturationPressure(T_mid, unitSystem);
        Pv = RH * Pws;
        W_calc = psychro.humidityRatio(Pv, P, unitSystem);

        if unitSystem == 1
            h_calc = 0.24 * T_mid + W_calc * (1061 + 0.444 * T_mid);
        else
            h_calc = 1.006 * T_mid + W_calc * (2501 + 1.86 * T_mid);
        end

        err = h - h_calc;

        if abs(err) < 0.1 || (T_high - T_low) < 0.01
            break;
        end

        if err > 0
            T_low = T_mid;
        else
            T_high = T_mid;
        end
    end
    T = T_mid;
    W = W_calc;
end
