function Twb = wetBulbFromTW(Tdb, W, P_atm)
    % WETBULBFROMTW Wet-bulb [C] from T [C], W [kg/kg], P [Pa]. Used by the live-sensor tab.
    %   Part of the 'psychro' package - call as psychro.wetBulbFromTW(...).
    %
    % FIX (portfolio clean-up): the original version used a simplified
    % relation, W = Ws(Twb) - 0.000662*(P/1000)*(Tdb - Twb)/1000, which is
    % dimensionally inconsistent and under-predicted wet bulb by ~3 C
    % (e.g. 20 C / 50 % RH gave 10.5 C instead of 13.7 C).
    % It now uses the same ASHRAE psychrometric relation as the chart.
    Twb = psychro.calculateWetBulb(Tdb, W, P_atm, 2);
end
