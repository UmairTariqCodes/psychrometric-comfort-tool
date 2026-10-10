# Psychrometric Comfort Tool

An interactive psychrometric chart and HVAC design tool in MATLAB, written for my BEng Mechanical Engineering individual project at the University of Sussex (2026, awarded 81%).

**This commit is the dissertation version, exactly as submitted.** Later commits restructure it, add automated tests, and extend it in Python with the full ISO 7730 comfort model and machine learning.

## What it does

All five tools share one calculation engine and sit in one window:

- **Point analysis:** click the chart, or enter any two of six properties (all 15 combinations), to get the full moist-air state.
- **Process analysis:** an eight-process HVAC classifier, including three-phase cooling and dehumidification with apparatus dew point and bypass factor.
- **Comfort zone:** an ASHRAE 55 zone that moves with clothing, activity and air speed.
- **Heat load:** a CLTD / UA·ΔT building load calculator that feeds into process analysis for equipment sizing.
- **Live sensor:** temperature, humidity and pressure from a BME280 over I²C via an Arduino, fed into the same engine in real time.

Equations come from ASHRAE Fundamentals (2021) and CIBSE Guide A (2015). SI and Imperial units are supported.

## Validation (from the dissertation)

- Four hand-calculated scenarios (heating, cooling and dehumidification, evaporative cooling, winter heating): all passed.
- A round-trip test of all 15 input combinations: all within 0.1 °C.
- Against CoolProp (IAPWS-based): saturation pressure within 0.044%, humidity ratio within 0.54%.

## Running it

MATLAB R2019b or later. The Live Sensor tab needs the MATLAB Support Package for Arduino Hardware.

```matlab
cd matlab
psychrometric_interactive
```

MIT licensed.
