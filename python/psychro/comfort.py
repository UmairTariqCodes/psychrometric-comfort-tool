"""Thermal comfort models.

* :func:`pmv_ppd` - the full ISO 7730 / Fanger PMV-PPD model (iterative
  clothing-surface heat balance). This is the upgrade over the MATLAB app.
* :func:`pmv_linear` - the simplified linear estimate used in the MATLAB app
  (kept so the two can be compared, see ``scripts/compare_pmv.py``).
* :func:`comfort_temperature_range` - the ASHRAE 55-style comfort band used to
  draw the comfort zone on the chart.
"""

from __future__ import annotations

import math
from dataclasses import dataclass


@dataclass(frozen=True)
class PMVResult:
    pmv: float   # predicted mean vote, -3 (cold) .. +3 (hot)
    ppd: float   # predicted percentage dissatisfied, %


def pmv_ppd(ta: float, tr: float, vel: float, rh: float, met: float, clo: float,
            wme: float = 0.0) -> PMVResult:
    """Full ISO 7730:2005 PMV / PPD (Annex D algorithm).

    Parameters
    ----------
    ta  : air temperature, C
    tr  : mean radiant temperature, C
    vel : relative air speed, m/s
    rh  : relative humidity, % (0-100)
    met : metabolic rate, met (1 met = 58.15 W/m2)
    clo : clothing insulation, clo (1 clo = 0.155 m2K/W)
    wme : external work, met (normally 0)

    >>> r = pmv_ppd(22, 22, 0.1, 60, 1.2, 0.5)   # ISO 7730 Table D.1 example
    >>> round(r.pmv, 2), round(r.ppd)
    (-0.75, 17)
    """
    pa = rh * 10 * math.exp(16.6536 - 4030.183 / (ta + 235))   # vapour pressure, Pa
    icl = 0.155 * clo
    m = met * 58.15
    w = wme * 58.15
    mw = m - w
    fcl = 1 + 1.29 * icl if icl <= 0.078 else 1.05 + 0.645 * icl
    hcf = 12.1 * math.sqrt(vel)
    taa = ta + 273.0
    tra = tr + 273.0

    # Iterate for clothing surface temperature
    tcla = taa + (35.5 - ta) / (3.5 * icl + 0.1)
    p1 = icl * fcl
    p2 = p1 * 3.96
    p3 = p1 * 100
    p4 = p1 * taa
    p5 = 308.7 - 0.028 * mw + p2 * (tra / 100) ** 4
    xn = tcla / 100
    xf = tcla / 50
    hc = hcf
    for _ in range(150):
        if abs(xn - xf) <= 0.00015:
            break
        xf = (xf + xn) / 2
        hcn = 2.38 * abs(100 * xf - taa) ** 0.25
        hc = max(hcf, hcn)
        xn = (p5 + p4 * hc - p2 * xf ** 4) / (100 + p3 * hc)
    else:
        raise RuntimeError("PMV clothing-temperature iteration did not converge")
    tcl = 100 * xn - 273

    # Heat-loss components, W/m2
    hl1 = 3.05e-3 * (5733 - 6.99 * mw - pa)          # skin diffusion
    hl2 = 0.42 * (mw - 58.15) if mw > 58.15 else 0.0  # sweating
    hl3 = 1.7e-5 * m * (5867 - pa)                    # latent respiration
    hl4 = 0.0014 * m * (34 - ta)                      # dry respiration
    hl5 = 3.96 * fcl * (xn ** 4 - (tra / 100) ** 4)   # radiation
    hl6 = fcl * hc * (tcl - ta)                       # convection

    ts = 0.303 * math.exp(-0.036 * m) + 0.028
    pmv = ts * (mw - hl1 - hl2 - hl3 - hl4 - hl5 - hl6)
    ppd = 100 - 95 * math.exp(-0.03353 * pmv ** 4 - 0.2179 * pmv ** 2)
    return PMVResult(pmv=pmv, ppd=ppd)


def comfort_temperature_range(clo: float, met: float, vel: float) -> tuple[float, float]:
    """Comfort-zone operative temperature band [C] used for the chart overlay.

    Linear interpolation between the ASHRAE 55 graphic-method reference bands
    (0.5 clo: 23.0-26.5 C, 1.0 clo: 20.0-24.0 C) with simple met / air-speed
    shifts - identical to ``psychro.getComfortTempRange`` in MATLAB.
    """
    lo = 23.0 + (20.0 - 23.0) / 0.5 * (clo - 0.5)
    hi = 26.5 + (24.0 - 26.5) / 0.5 * (clo - 0.5)
    shift = -0.8 * (met - 1.1) / 0.1 + 1.0 * (vel - 0.1) / 0.3
    return lo + shift, hi + shift


def pmv_linear(to: float, rh: float, clo: float, met: float, vel: float) -> float:
    """Simplified linear PMV used in the MATLAB app (``psychro.estimatePMV``).

    ``rh`` is a fraction (0-1). Kept for comparison with :func:`pmv_ppd`.
    """
    lo, hi = comfort_temperature_range(clo, met, vel)
    pmv = 0.33 * (to - (lo + hi) / 2) + (rh * 100 - 50) * 0.005
    return max(-3.0, min(3.0, pmv))
