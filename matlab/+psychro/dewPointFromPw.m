function Tdp = dewPointFromPw(Pw)
    % DEWPOINTFROMPW Dew point [C] from vapour pressure [Pa] (inverted Magnus formula). Used by the live-sensor tab.
    %   Part of the 'psychro' package - call as psychro.dewPointFromPw(...).
    %
    % Approximate dew point from partial water vapour pressure (Pa)
    % Using Magnus formula inverted
    if Pw <= 0
        Tdp = -273.15;
        return;
    end
    alpha = log(Pw / 611.21);
    Tdp = (257.14 * alpha) / (18.678 - alpha);
end
