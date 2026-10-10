"""Machine-learning comfort models.

Two stages, both built on the physics in :mod:`psychro.comfort`:

1. **Pipeline check against physics** (runs out of the box). Label random
   indoor conditions with the exact ISO 7730 PMV, train a model on them, and
   measure how close it gets. This validates the ML pipeline on a problem with a
   known answer, and also quantifies how far the linear shortcut in the
   original MATLAB app was from the full model.

2. **Learning from real people** (needs the free ASHRAE Global Thermal Comfort
   Database II). PMV is known to mispredict how real occupants feel, especially
   in naturally ventilated buildings. Train on ~100k real thermal-sensation
   votes and compare the model against PMV on held-out data.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.metrics import mean_absolute_error, r2_score
from sklearn.model_selection import train_test_split

from .comfort import pmv_linear, pmv_ppd

FEATURES = ["ta", "tr", "vel", "rh", "met", "clo"]


# --------------------------------------------------------------------------- #
# Stage 1 - PMV surrogate
# --------------------------------------------------------------------------- #
def sample_conditions(n: int, seed: int = 0) -> pd.DataFrame:
    """Random but realistic indoor conditions (within ISO 7730 validity limits)."""
    rng = np.random.default_rng(seed)
    ta = rng.uniform(16, 32, n)
    return pd.DataFrame({
        "ta": ta,
        "tr": np.clip(ta + rng.normal(0, 1.5, n), 10, 40),
        "vel": rng.uniform(0.05, 1.0, n),
        "rh": rng.uniform(20, 80, n),          # %
        "met": rng.uniform(0.9, 2.0, n),
        "clo": rng.uniform(0.3, 1.5, n),
    })


def label_with_pmv(df: pd.DataFrame) -> pd.DataFrame:
    """Add exact ISO 7730 PMV and the MATLAB linear estimate as columns."""
    out = df.copy()
    out["pmv"] = [pmv_ppd(r.ta, r.tr, r.vel, r.rh, r.met, r.clo).pmv for r in df.itertuples()]
    # The linear estimate uses operative temperature ~ mean of air and radiant
    out["pmv_linear"] = [pmv_linear((r.ta + r.tr) / 2, r.rh / 100, r.clo, r.met, r.vel)
                         for r in df.itertuples()]
    return out


@dataclass
class SurrogateReport:
    n_train: int
    n_test: int
    mae_ml: float
    r2_ml: float
    mae_linear: float
    r2_linear: float


def train_pmv_surrogate(n: int = 20_000, seed: int = 0):
    """Train a gradient-boosted model to reproduce exact PMV. Returns ``(model, report, test_df)``."""
    data = label_with_pmv(sample_conditions(n, seed))
    train, test = train_test_split(data, test_size=0.2, random_state=seed)

    model = HistGradientBoostingRegressor(max_iter=600, learning_rate=0.08,
                                          max_leaf_nodes=63, random_state=seed)
    model.fit(train[FEATURES], train["pmv"])
    test = test.copy()
    test["pmv_ml"] = model.predict(test[FEATURES])

    report = SurrogateReport(
        n_train=len(train), n_test=len(test),
        mae_ml=mean_absolute_error(test["pmv"], test["pmv_ml"]),
        r2_ml=r2_score(test["pmv"], test["pmv_ml"]),
        mae_linear=mean_absolute_error(test["pmv"], test["pmv_linear"]),
        r2_linear=r2_score(test["pmv"], test["pmv_linear"]),
    )
    return model, report, test


# --------------------------------------------------------------------------- #
# Stage 2 - learn from real occupants (ASHRAE Global Thermal Comfort DB II)
# --------------------------------------------------------------------------- #
# Download (free): https://doi.org/10.6078/D1F671  (Dryad) or the CBE GitHub
# repository "ashrae-db-II". Column names vary slightly between releases, so
# columns are matched by keywords; check the printout the first time you run it.
DB2_COLUMNS = {
    "ta": ["air temperature (c)", "ta"],
    "tr": ["radiant temperature (c)", "radiant temperature", "tr"],
    "vel": ["air velocity (m/s)", "air velocity", "vel"],
    "rh": ["relative humidity (%)", "relative humidity", "rh"],
    "met": ["met"],
    "clo": ["clo"],
    "tsv": ["thermal sensation", "tsv"],
    "t_out": ["outdoor monthly air temperature (c)", "outdoor monthly air temperature", "t_mot_isd"],
}


def _match_columns(df: pd.DataFrame) -> dict:
    lower = {c.lower().strip(): c for c in df.columns}
    found = {}
    for key, candidates in DB2_COLUMNS.items():
        for cand in candidates:
            if cand in lower:
                found[key] = lower[cand]
                break
    return found


def load_ashrae_db2(path: str | Path) -> pd.DataFrame:
    """Load and clean the ASHRAE DB II CSV into the standard feature columns + ``tsv``."""
    raw = pd.read_csv(path, low_memory=False)
    cols = _match_columns(raw)
    missing = {"ta", "vel", "rh", "met", "clo", "tsv"} - set(cols)
    if missing:
        raise KeyError(f"Could not find columns for {missing}. Columns are: {list(raw.columns)}")
    df = raw[list(cols.values())].rename(columns={v: k for k, v in cols.items()})
    if "tr" not in df:
        df["tr"] = df["ta"]
    df["tr"] = df["tr"].fillna(df["ta"])
    df = df.apply(pd.to_numeric, errors="coerce").dropna(subset=FEATURES + ["tsv"])
    # Keep the ISO 7730 applicability range so PMV is a fair baseline
    df = df[df.ta.between(10, 30) & df.tr.between(10, 40) & df.vel.between(0, 1)
            & df.rh.between(0, 100) & df.met.between(0.8, 4) & df.clo.between(0, 2)
            & df.tsv.between(-3, 3)]
    return df.reset_index(drop=True)


def compare_ml_vs_pmv(df: pd.DataFrame, seed: int = 0) -> dict:
    """Train on real votes and compare against PMV on a held-out set."""
    feats = FEATURES + (["t_out"] if "t_out" in df and df["t_out"].notna().mean() > 0.8 else [])
    data = df.dropna(subset=feats).copy()
    train, test = train_test_split(data, test_size=0.2, random_state=seed)
    model = HistGradientBoostingRegressor(max_iter=400, learning_rate=0.05, random_state=seed)
    model.fit(train[feats], train["tsv"])
    pred_ml = model.predict(test[feats])
    pred_pmv = [pmv_ppd(r.ta, r.tr, r.vel, r.rh, r.met, r.clo).pmv for r in test.itertuples()]
    return {
        "features": feats,
        "n_train": len(train), "n_test": len(test),
        "mae_ml": mean_absolute_error(test["tsv"], pred_ml),
        "mae_pmv": mean_absolute_error(test["tsv"], pred_pmv),
        "within_0.5_ml": float(np.mean(np.abs(test["tsv"] - pred_ml) <= 0.5)),
        "within_0.5_pmv": float(np.mean(np.abs(test["tsv"] - np.asarray(pred_pmv)) <= 0.5)),
        "model": model,
    }
