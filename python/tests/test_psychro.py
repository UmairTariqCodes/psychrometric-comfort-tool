"""Tests against published reference values.

* Saturation pressure: ASHRAE Handbook - Fundamentals, Ch. 1 Table 3.
* 20 C / 50 % RH state point: cross-checked against CoolProp (HAPropsSI).
* PMV / PPD: ISO 7730:2005 Annex D Table D.1, and the CBE pythermalcomfort library.
"""

import pytest

import psychro as ps


@pytest.mark.parametrize("t, ref", [(-10, 259.90), (0, 611.21), (20, 2339.3),
                                    (30, 4246.9), (40, 7384.9)])
def test_saturation_pressure_matches_ashrae(t, ref):
    assert ps.saturation_pressure(t) == pytest.approx(ref, rel=0.005)


def test_state_20c_50rh():
    s = ps.state(20, rh=0.5)
    assert s.w == pytest.approx(0.00726, abs=5e-5)
    assert s.tdp == pytest.approx(9.27, abs=0.05)
    assert s.twb == pytest.approx(13.78, abs=0.05)   # CoolProp: 13.776
    assert s.h == pytest.approx(38.55, abs=0.1)
    assert s.v == pytest.approx(0.840, abs=1e-3)


@pytest.mark.parametrize("t, twb", [(30, 20), (25, 18), (35, 30), (10, 5)])
def test_wet_bulb_round_trip(t, twb):
    w = ps.humidity_ratio_from_wet_bulb(t, twb)
    assert ps.wet_bulb(t, w) == pytest.approx(twb, abs=1e-6)


def test_state_inputs_are_consistent():
    a = ps.state(24, rh=0.45)
    b = ps.state(24, w=a.w)
    c = ps.state(24, twb=a.twb)
    assert b.rh == pytest.approx(a.rh)
    assert c.w == pytest.approx(a.w, rel=1e-6)


def test_state_requires_exactly_one_humidity_input():
    with pytest.raises(ValueError):
        ps.state(20)
    with pytest.raises(ValueError):
        ps.state(20, rh=0.5, w=0.01)


def test_apparatus_dew_point_on_saturation_curve():
    t, w = ps.apparatus_dew_point(24, 0.0093, 0.75)
    assert t < 24
    assert w == pytest.approx(ps.humidity_ratio(ps.saturation_pressure(t)))


def test_pmv_iso7730_table_d1():
    r = ps.pmv_ppd(ta=22, tr=22, vel=0.1, rh=60, met=1.2, clo=0.5)
    assert r.pmv == pytest.approx(-0.75, abs=0.01)
    assert r.ppd == pytest.approx(17, abs=0.5)


@pytest.mark.parametrize("args", [(22, 22, 0.1, 60, 1.2, 0.5), (27, 27, 0.3, 50, 1.1, 0.5),
                                  (19, 21, 0.05, 40, 1.0, 1.0), (30, 32, 0.8, 70, 1.6, 0.3)])
def test_pmv_matches_pythermalcomfort(args):
    ptc = pytest.importorskip("pythermalcomfort.models")
    ta, tr, vel, rh, met, clo = args
    ref = ptc.pmv_ppd_iso(tdb=ta, tr=tr, vr=vel, rh=rh, met=met, clo=clo,
                          model="7730-2005", limit_inputs=False)
    mine = ps.pmv_ppd(*args)
    assert mine.pmv == pytest.approx(float(ref.pmv), abs=0.01)
    assert mine.ppd == pytest.approx(float(ref.ppd), abs=0.1)


def test_comfort_range_reference_points():
    assert ps.comfort_temperature_range(0.5, 1.1, 0.1) == pytest.approx((23.0, 26.5))
    assert ps.comfort_temperature_range(1.0, 1.1, 0.1) == pytest.approx((20.0, 24.0))
