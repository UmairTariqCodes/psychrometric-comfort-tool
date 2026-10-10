function W = humidityRatioFromWetBulb(Tdb, Twb, P, unitSystem)
    % HUMIDITYRATIOFROMWETBULB Humidity ratio from dry-bulb and wet-bulb temperature (ASHRAE psychrometric relation).
    %   Part of the 'psychro' package - call as psychro.humidityRatioFromWetBulb(...).
    if Twb > Tdb
        W = 0;
        return;
    end

    Pws_wb = psychro.saturationPressure(Twb, unitSystem);
    Ws_wb = psychro.humidityRatio(Pws_wb, P, unitSystem);

    if unitSystem == 1
        W = ((1061 + 0.444 * Twb) * Ws_wb - 0.24 * (Tdb - Twb)) / (1061 + 0.444 * Tdb);
    else
        W = ((2501 + 1.86 * Twb) * Ws_wb - 1.006 * (Tdb - Twb)) / (2501 + 1.86 * Tdb);
    end
    W = max(0, min(W, 0.03));
end
