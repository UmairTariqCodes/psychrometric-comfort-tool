function Pws = saturationPressure(T, unitSystem)
    % SATURATIONPRESSURE Saturation vapour pressure over water/ice (Magnus/Buck-type fit). SI: T [C] -> Pa. IP: T [F] -> psia.
    %   Part of the 'psychro' package - call as psychro.saturationPressure(...).
    if unitSystem == 1  % IP (T in F)
        Tc = (T - 32) * 5/9;
        if Tc >= 0
            Pws_Pa = 611.21 * exp((18.678 - Tc/234.5) * Tc / (257.14 + Tc));
        else
            Pws_Pa = 611.2 * exp(21.875 * Tc / (Tc + 265.5));
        end
        Pws = Pws_Pa * 0.0001450377;
    else  % SI (T in C)
        if T >= 0
            Pws = 611.21 * exp((18.678 - T/234.5) * T / (257.14 + T));
        else
            Pws = 611.2 * exp(21.875 * T / (T + 265.5));
        end
    end
end
