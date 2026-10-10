import numpy as np
import pandas as pd

from psychro.ml import compare_ml_vs_pmv, label_with_pmv, load_ashrae_db2, sample_conditions


def test_labels_are_finite():
    df = label_with_pmv(sample_conditions(50))
    assert np.isfinite(df["pmv"]).all()


def test_db2_loader_matches_columns_and_runs(tmp_path):
    # Tiny fake file using DB II-style column names
    rng = np.random.default_rng(1)
    n = 300
    ta = rng.uniform(18, 29, n)
    fake = pd.DataFrame({
        "Air temperature (C)": ta,
        "Radiant temperature (C)": ta + 0.5,
        "Air velocity (m/s)": rng.uniform(0.05, 0.5, n),
        "Relative humidity (%)": rng.uniform(30, 70, n),
        "Met": 1.2,
        "Clo": rng.uniform(0.4, 1.0, n),
        "Thermal sensation": np.clip(np.round((ta - 24) / 2), -3, 3),
    })
    path = tmp_path / "db2.csv"
    fake.to_csv(path, index=False)
    df = load_ashrae_db2(path)
    assert {"ta", "tr", "vel", "rh", "met", "clo", "tsv"} <= set(df.columns)
    res = compare_ml_vs_pmv(df)
    assert res["mae_ml"] >= 0 and res["mae_pmv"] >= 0
