function T = temperatureFromSatPressure(Pws, unitSystem)
    % TEMPERATUREFROMSATPRESSURE Inverse of saturationPressure: temperature at which Pws is reached.
    %   Part of the 'psychro' package - call as psychro.temperatureFromSatPressure(...).
    if unitSystem == 1
        T_low = -40; T_high = 200;
    else
        T_low = -40; T_high = 100;
    end

    for iter = 1:100
        T_mid = (T_low + T_high) / 2;
        Pws_calc = psychro.saturationPressure(T_mid, unitSystem);
        err = Pws - Pws_calc;

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
end
