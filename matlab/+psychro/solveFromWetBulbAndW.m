function [T, W] = solveFromWetBulbAndW(Twb, W, P, unitSystem)
    % SOLVEFROMWETBULBANDW State point (T, W) from wet-bulb temperature and humidity ratio.
    %   Part of the 'psychro' package - call as psychro.solveFromWetBulbAndW(...).
    if unitSystem == 1
        T_low = Twb; T_high = Twb + 100;
    else
        T_low = Twb; T_high = Twb + 50;
    end

    for iter = 1:100
        T_mid = (T_low + T_high) / 2;
        W_calc = psychro.humidityRatioFromWetBulb(T_mid, Twb, P, unitSystem);

        err = W - W_calc;

        if abs(err) < 0.000001 || (T_high - T_low) < 0.01
            break;
        end

        if err < 0
            T_low = T_mid;
        else
            T_high = T_mid;
        end
    end
    T = T_mid;
end
