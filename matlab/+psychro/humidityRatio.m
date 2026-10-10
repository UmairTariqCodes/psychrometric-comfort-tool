function W = humidityRatio(Pw, P, ~)
    % HUMIDITYRATIO Humidity ratio W [kg/kg or lb/lb] from vapour pressure Pw and total pressure P (same units).
    %   Part of the 'psychro' package - call as psychro.humidityRatio(...).
    W = 0.62198 * Pw / (P - Pw);
    W = max(0, W);
end
