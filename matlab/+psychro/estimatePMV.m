function pmv = estimatePMV(To, RH, cloVal, metVal, airVel, unitSystem)
    % ESTIMATEPMV Simplified (linearised) PMV estimate. NOT the full ISO 7730 Fanger model - see python/psychro/comfort.py for that.
    %   Part of the 'psychro' package - call as psychro.estimatePMV(...).
    %
    % Simplified PMV estimate based on Fanger's model
    % To = operative temperature, RH = relative humidity (0-1)
    %
    % This is a linearised approximation suitable for the
    % typical HVAC range. For rigorous PMV, the full iterative
    % Fanger model would be needed.

    % Convert to Celsius if IP
    if unitSystem == 1
        To_C = (To - 32) * 5/9;
    else
        To_C = To;
    end

    % Neutral (comfort) temperature for given clo/met/airVel
    [T_lo, T_hi] = psychro.getComfortTempRange(cloVal, metVal, airVel, 2);  % always in C
    T_neutral = (T_lo + T_hi) / 2;

    % PMV sensitivity: approximately 0.33 PMV per degree C deviation
    % from neutral for typical indoor conditions
    % (derived from Fanger model linearisation at typical conditions)
    pmv_per_degC = 0.33;

    % Humidity correction: higher humidity makes warm side feel warmer
    % At 50% RH: no correction. Each 10% above/below shifts ~0.05 PMV
    RH_pct = RH * 100;
    humidity_correction = (RH_pct - 50) * 0.005;

    % Base PMV from temperature deviation
    pmv = pmv_per_degC * (To_C - T_neutral) + humidity_correction;

    % Clamp to reasonable range
    pmv = max(-3, min(3, pmv));
end
