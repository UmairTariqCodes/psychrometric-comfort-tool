function Tdp = calculateDewPoint(Pv, unitSystem)
    % CALCULATEDEWPOINT Dew-point temperature from vapour pressure (bisection on saturation curve).
    %   Part of the 'psychro' package - call as psychro.calculateDewPoint(...).
    if unitSystem == 1
        T_low = -40;  T_high = 200;  tol = 0.001;
    else
        T_low = -60;  T_high = 80;   tol = 1;
    end

    for iter = 1:100
        T_mid = (T_low + T_high) / 2;
        Pws_mid = psychro.saturationPressure(T_mid, unitSystem);
        err = Pv - Pws_mid;

        if abs(err) < tol || (T_high - T_low) < 0.01
            break;
        end

        if err > 0
            T_low = T_mid;
        else
            T_high = T_mid;
        end
    end
    Tdp = T_mid;
end
