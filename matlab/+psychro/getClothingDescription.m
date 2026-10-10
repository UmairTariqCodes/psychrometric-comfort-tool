function desc = getClothingDescription(cloVal)
    % GETCLOTHINGDESCRIPTION Plain-English clothing description for a clo value.
    %   Part of the 'psychro' package - call as psychro.getClothingDescription(...).
    %
    % Return a description of typical clothing for a given clo value
    if cloVal <= 0.35
        desc = 'Shorts + T-shirt';
    elseif cloVal <= 0.45
        desc = 'Light trousers + T-shirt';
    elseif cloVal <= 0.55
        desc = 'Light trousers + short-sleeve shirt';
    elseif cloVal <= 0.65
        desc = 'Trousers + short-sleeve shirt + socks';
    elseif cloVal <= 0.75
        desc = 'Trousers + long-sleeve shirt';
    elseif cloVal <= 0.85
        desc = 'Trousers + long-sleeve shirt + jumper';
    elseif cloVal <= 0.95
        desc = 'Trousers + long-sleeve shirt + jacket';
    elseif cloVal <= 1.05
        desc = 'Trousers + shirt + jacket + tie';
    elseif cloVal <= 1.15
        desc = 'Trousers + shirt + jacket + waistcoat';
    elseif cloVal <= 1.25
        desc = 'Suit + waistcoat + overcoat (light)';
    elseif cloVal <= 1.35
        desc = 'Heavy suit + overcoat';
    else
        desc = 'Heavy winter clothing + overcoat';
    end
end
