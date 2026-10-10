function [T, W] = solveFromWetBulbAndRH(Twb, RH, P, unitSystem)
    % SOLVEFROMWETBULBANDRH State point (T, W) from wet-bulb temperature and relative humidity.
    %   Part of the 'psychro' package - call as psychro.solveFromWetBulbAndRH(...).
    if unitSystem == 1
        T_low = Twb; T_high = Twb + 100;
    else
        T_low = Twb; T_high = Twb + 50;
    end

    for iter = 1:100
        T_mid = (T_low + T_high) / 2;
        W_calc = psychro.humidityRatioFromWetBulb(T_mid, Twb, P, unitSystem);
        Pws = psychro.saturationPressure(T_mid, unitSystem);
        Pv = W_calc * P / (0.62198 + W_calc);
        RH_calc = Pv / Pws;

        err = RH - RH_calc;

        if abs(err) < 0.001 || (T_high - T_low) < 0.01
            break;
        end

        if err < 0
            T_low = T_mid;
        else
            T_high = T_mid;
        end
    end
    T = T_mid;
    W = W_calc;
end
