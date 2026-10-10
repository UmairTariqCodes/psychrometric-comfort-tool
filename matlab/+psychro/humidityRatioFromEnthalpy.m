function W = humidityRatioFromEnthalpy(h, T, unitSystem)
    % HUMIDITYRATIOFROMENTHALPY Humidity ratio from moist-air enthalpy h and dry-bulb temperature T.
    %   Part of the 'psychro' package - call as psychro.humidityRatioFromEnthalpy(...).
    if unitSystem == 1
        Cp = 0.24; hfg = 1061; Cpv = 0.444;
    else
        Cp = 1.006; hfg = 2501; Cpv = 1.86;
    end
    W = (h - Cp * T) / (hfg + Cpv * T);
    W = max(0, min(W, 0.03));
end
