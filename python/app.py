"""Web demo: interactive psychrometric chart + thermal comfort.

    streamlit run app.py

Deploy free on Streamlit Community Cloud or Hugging Face Spaces so anyone
can try it in a browser (no MATLAB needed).
"""

import matplotlib.pyplot as plt
import numpy as np
import streamlit as st

import psychro as ps

st.set_page_config(page_title="Psychrometric Comfort Tool", layout="wide")
st.title("Psychrometric chart & thermal comfort")
st.caption("Python port of a MATLAB dissertation tool - full ISO 7730 PMV model")

with st.sidebar:
    st.header("Air state")
    t = st.slider("Dry-bulb temperature (C)", 10.0, 40.0, 24.0, 0.5)
    rh = st.slider("Relative humidity (%)", 5, 95, 50) / 100
    tr = st.slider("Mean radiant temperature (C)", 10.0, 40.0, t, 0.5)
    st.header("Occupant")
    clo = st.slider("Clothing (clo)", 0.3, 1.5, 0.6, 0.05)
    met = st.slider("Metabolic rate (met)", 0.8, 2.5, 1.1, 0.1)
    vel = st.slider("Air speed (m/s)", 0.05, 1.0, 0.1, 0.05)

s = ps.state(t, rh=rh)
comfort = ps.pmv_ppd(t, tr, vel, rh * 100, met, clo)

col_chart, col_props = st.columns([2, 1])

with col_props:
    st.subheader("Properties")
    st.metric("Humidity ratio", f"{s.w * 1000:.2f} g/kg")
    st.metric("Dew point", f"{s.tdp:.1f} C")
    st.metric("Wet bulb", f"{s.twb:.1f} C")
    st.metric("Enthalpy", f"{s.h:.1f} kJ/kg")
    st.metric("Specific volume", f"{s.v:.3f} m3/kg")
    st.subheader("Comfort (ISO 7730)")
    st.metric("PMV", f"{comfort.pmv:+.2f}", help="-3 cold ... 0 neutral ... +3 hot")
    st.metric("PPD", f"{comfort.ppd:.0f} % dissatisfied")
    if abs(comfort.pmv) <= 0.5:
        st.success("Within the ISO 7730 Category B comfort band (|PMV| <= 0.5)")
    else:
        st.warning("Outside the comfort band (|PMV| > 0.5)")

with col_chart:
    temps = np.linspace(0, 45, 200)
    fig, ax = plt.subplots(figsize=(8, 5.5))
    for r in np.arange(0.1, 1.01, 0.1):
        w = [ps.humidity_ratio_from_rh(x, r) * 1000 for x in temps]
        ax.plot(temps, w, color="#2a6fdb" if r == 1 else "#9bb7e0",
                lw=1.6 if r >= 0.999 else 0.7)
        # label each RH curve at its last point inside the plot area
        inside = [i for i, wi in enumerate(w) if wi <= 28.5]
        if inside and r < 0.999:
            i = inside[-1]
            ax.text(temps[i], w[i], f"{r:.0%}", fontsize=7, color="#5a7bb0",
                    ha="right", va="bottom", clip_on=True)
    lo, hi = ps.comfort_temperature_range(clo, met, vel)
    zone_t = np.linspace(lo, hi, 30)
    bottom = [ps.humidity_ratio_from_rh(x, 0.3) * 1000 for x in zone_t]
    top = [min(ps.humidity_ratio_from_rh(x, 0.6), 0.012) * 1000 for x in zone_t]
    ax.fill_between(zone_t, bottom, top, color="#f4a259", alpha=0.25, label="Comfort zone")
    ax.plot(t, s.w * 1000, "o", color="#d1495b", ms=9, label="Current state")
    ax.set_xlim(0, 45)
    ax.set_ylim(0, 30)
    ax.set_xlabel("Dry-bulb temperature (C)")
    ax.set_ylabel("Humidity ratio (g/kg dry air)")
    ax.yaxis.tick_right()
    ax.yaxis.set_label_position("right")
    ax.grid(alpha=0.25)
    ax.legend(loc="upper left")
    st.pyplot(fig)
