"""Moist-air (psychrometric) properties in SI units.

Python port of the ``+psychro`` MATLAB package. Units throughout:

* temperatures in degrees C
* pressures in Pa
* humidity ratio ``W`` in kg water / kg dry air
* relative humidity ``rh`` as a fraction (0-1)
* enthalpy in kJ/kg dry air
* specific volume in m^3/kg dry air

The saturation-pressure fit is the same Magnus/Buck-type correlation used in
the MATLAB app (within ~0.1 % of the ASHRAE Handbook table between -10 and
40 C), so the two implementations give identical answers.
"""

from __future__ import annotations

from dataclasses import dataclass, asdict

import numpy as np
from scipy.optimize import brentq

P_ATM = 101_325.0          # standard sea-level pressure, Pa
EPS = 0.62198              # ratio of molar masses, water / dry air
R_DA = 287.055             # gas constant of dry air, J/(kg K)
CP_DA = 1.006              # kJ/(kg K)
CP_V = 1.86                # kJ/(kg K)
H_FG = 2501.0              # kJ/kg at 0 C


def saturation_pressure(t: float | np.ndarray) -> float | np.ndarray:
    """Saturation vapour pressure [Pa] over water (t >= 0 C) or ice (t < 0 C)."""
    t = np.asarray(t, dtype=float)
    over_water = 611.21 * np.exp((18.678 - t / 234.5) * t / (257.14 + t))
    over_ice = 611.2 * np.exp(21.875 * t / (t + 265.5))
    out = np.where(t >= 0, over_water, over_ice)
    return out.item() if out.ndim == 0 else out


def humidity_ratio(pv: float, p: float = P_ATM) -> float:
    """Humidity ratio from vapour partial pressure ``pv`` and total pressure ``p``."""
    return max(0.0, EPS * pv / (p - pv))


def vapour_pressure(w: float, p: float = P_ATM) -> float:
    """Vapour partial pressure [Pa] from humidity ratio."""
    return w * p / (EPS + w)


def humidity_ratio_from_rh(t: float, rh: float, p: float = P_ATM) -> float:
    """Humidity ratio from dry-bulb temperature and relative humidity (0-1)."""
    return humidity_ratio(rh * saturation_pressure(t), p)


def humidity_ratio_from_wet_bulb(t: float, twb: float, p: float = P_ATM) -> float:
    """Humidity ratio from dry-bulb and thermodynamic wet-bulb temperature.

    Uses ASHRAE Handbook - Fundamentals (2017) Ch. 1 Eq. 33 (twb above freezing).
    This is slightly more exact than the simplified form in the MATLAB app
    (difference < 0.1 C in wet bulb over normal HVAC conditions).
    """
    if twb > t:
        raise ValueError("wet-bulb temperature cannot exceed dry-bulb temperature")
    ws = humidity_ratio(saturation_pressure(twb), p)
    return max(0.0, ((H_FG - 2.326 * twb) * ws - CP_DA * (t - twb))
               / (H_FG + CP_V * t - 4.186 * twb))


def enthalpy(t: float, w: float) -> float:
    """Moist-air enthalpy [kJ/kg dry air]."""
    return CP_DA * t + w * (H_FG + CP_V * t)


def specific_volume(t: float, w: float, p: float = P_ATM) -> float:
    """Moist-air specific volume [m^3/kg dry air]."""
    return R_DA * (t + 273.15) / p * (1 + 1.6078 * w)


def dew_point(pv: float) -> float:
    """Dew-point temperature [C] from vapour pressure [Pa]."""
    if pv <= 0:
        return float("-inf")
    return brentq(lambda t: saturation_pressure(t) - pv, -80.0, 100.0)


def wet_bulb(t: float, w: float, p: float = P_ATM) -> float:
    """Thermodynamic wet-bulb temperature [C] from dry-bulb and humidity ratio."""
    f = lambda twb: humidity_ratio_from_wet_bulb(t, twb, p) - w  # noqa: E731
    lo = -40.0
    if f(t) <= 0:  # at or above saturation
        return t
    return brentq(f, lo, t)


@dataclass(frozen=True)
class State:
    """A fully defined moist-air state point."""

    t: float      # dry-bulb, C
    w: float      # humidity ratio, kg/kg
    rh: float     # relative humidity, 0-1
    tdp: float    # dew point, C
    twb: float    # wet bulb, C
    h: float      # enthalpy, kJ/kg
    v: float      # specific volume, m3/kg
    pv: float     # vapour pressure, Pa
    p: float      # total pressure, Pa

    def as_dict(self) -> dict:
        return asdict(self)


def state(t: float, *, rh: float | None = None, w: float | None = None,
          twb: float | None = None, p: float = P_ATM) -> State:
    """Build a :class:`State` from dry-bulb ``t`` plus one of ``rh``, ``w`` or ``twb``.

    >>> s = state(20, rh=0.5)
    >>> round(s.twb, 1)
    13.8
    """
    given = [x is not None for x in (rh, w, twb)]
    if sum(given) != 1:
        raise ValueError("give exactly one of rh, w or twb")
    if rh is not None:
        w = humidity_ratio_from_rh(t, rh, p)
    elif twb is not None:
        w = humidity_ratio_from_wet_bulb(t, twb, p)
    pv = vapour_pressure(w, p)
    return State(
        t=t,
        w=w,
        rh=min(1.0, pv / saturation_pressure(t)),
        tdp=dew_point(pv),
        twb=wet_bulb(t, w, p),
        h=enthalpy(t, w),
        v=specific_volume(t, w, p),
        pv=pv,
        p=p,
    )


def apparatus_dew_point(t_room: float, w_room: float, shr: float,
                        p: float = P_ATM) -> tuple[float, float]:
    """Apparatus dew point: where the room sensible-heat-ratio line meets saturation.

    Returns ``(t_adp, w_adp)``; raises ``ValueError`` if the line never
    reaches the saturation curve (e.g. SHR >= 1).
    """
    if not 0 < shr < 1:
        raise ValueError("SHR must be strictly between 0 and 1")
    slope = (1 - shr) * CP_DA / (shr * H_FG)        # dW/dT along the SHR line
    f = lambda t: (w_room + slope * (t - t_room)) - humidity_ratio(saturation_pressure(t), p)  # noqa: E731
    t_adp = brentq(f, -10.0, t_room)
    return t_adp, humidity_ratio(saturation_pressure(t_adp), p)
