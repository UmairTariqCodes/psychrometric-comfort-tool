function [T, W] = solveFromWetBulbAndEnthalpy(Twb, h, P, unitSystem)
    % SOLVEFROMWETBULBANDENTHALPY State point (T, W) from wet-bulb temperature and enthalpy.
    %   Part of the 'psychro' package - call as psychro.solveFromWetBulbAndEnthalpy(...).
    if unitSystem == 1
        T_low = Twb; T_high = Twb + 100;
    else
        T_low = Twb; T_high = Twb + 50;
    end

    for iter = 1:100
        T_mid = (T_low + T_high) / 2;
        W_calc = psychro.humidityRatioFromWetBulb(T_mid, Twb, P, unitSystem);

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
