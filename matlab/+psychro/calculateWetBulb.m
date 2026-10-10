function Twb = calculateWetBulb(Tdb, W, P, unitSystem)
    % CALCULATEWETBULB Thermodynamic wet-bulb temperature from T, W, P (bisection).
    %   Part of the 'psychro' package - call as psychro.calculateWetBulb(...).
    if unitSystem == 1
        Twb_low = -20;
    else
        Twb_low = -10;
    end
    Twb_high = Tdb;

    for iter = 1:100
        Twb_mid = (Twb_low + Twb_high) / 2;
        W_calc = psychro.humidityRatioFromWetBulb(Tdb, Twb_mid, P, unitSystem);
        err = W - W_calc;

        if abs(err) < 0.000001 || (Twb_high - Twb_low) < 0.01
            break;
        end

        if err > 0
            Twb_low = Twb_mid;
        else
            Twb_high = Twb_mid;
        end
    end
    Twb = Twb_mid;
end
