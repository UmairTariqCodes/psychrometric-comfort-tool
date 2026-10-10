function props = calculateProperties(T, W, P, unitSystem)
    % CALCULATEPROPERTIES All moist-air properties (Pws, Pv, RH, Tdp, Twb, h, v) from dry-bulb T and humidity ratio W.
    %   Part of the 'psychro' package - call as psychro.calculateProperties(...).
    props = struct();
    props.T = T;
    props.W = W;

    Pws = psychro.saturationPressure(T, unitSystem);
    props.Pws = Pws;

    props.Pv = W * P / (0.62198 + W);

    props.RH = props.Pv / Pws;
    if props.RH > 1
        props.RH = 1;
    end

    props.Tdp = psychro.calculateDewPoint(props.Pv, unitSystem);
    props.Twb = psychro.calculateWetBulb(T, W, P, unitSystem);

    if unitSystem == 1
        props.h = 0.24 * T + W * (1061 + 0.444 * T);
    else
        props.h = 1.006 * T + W * (2501 + 1.86 * T);
    end

    if unitSystem == 1
        T_R = T + 459.67;
        P_psf = P * 144;
        Ra = 53.352;
        props.v = Ra * T_R / P_psf * (1 + 1.6078 * W);
    else
        T_K = T + 273.15;
        Ra = 287.055;
        props.v = Ra * T_K / P * (1 + 1.6078 * W);
    end
end
