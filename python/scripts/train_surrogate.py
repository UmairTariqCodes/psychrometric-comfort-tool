"""Stage 1: check the ML pipeline against the exact ISO 7730 PMV model, and
measure how far the linear estimate from the original MATLAB app was off.

    python scripts/train_surrogate.py

Writes results/surrogate_metrics.json and docs/images/pmv_surrogate.png.
"""

import json
import sys
from pathlib import Path

import joblib
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from psychro.ml import train_pmv_surrogate  # noqa: E402

REPO = ROOT.parent
(ROOT / "results").mkdir(exist_ok=True)
(REPO / "docs" / "images").mkdir(parents=True, exist_ok=True)

model, rep, test = train_pmv_surrogate(n=20_000)

metrics = {
    "n_train": rep.n_train, "n_test": rep.n_test,
    "ml_surrogate": {"mae": round(rep.mae_ml, 4), "r2": round(rep.r2_ml, 4)},
    "matlab_linear_estimate": {"mae": round(rep.mae_linear, 4), "r2": round(rep.r2_linear, 4)},
}
# Fairer check: the linear estimate was only intended for typical office
# conditions (ASHRAE 55 graphic-method range), so score it there too.
office = test[test.met.between(1.0, 1.3) & (test.vel < 0.2) & test.clo.between(0.5, 1.0)]
metrics["office_conditions_only"] = {
    "n": len(office),
    "mae_linear": round(float((office.pmv - office.pmv_linear).abs().mean()), 4),
    "mae_ml": round(float((office.pmv - office.pmv_ml).abs().mean()), 4),
}
(ROOT / "results" / "surrogate_metrics.json").write_text(json.dumps(metrics, indent=2))
joblib.dump(model, ROOT / "results" / "pmv_surrogate.joblib")
print(json.dumps(metrics, indent=2))

# Figure: predicted vs exact PMV for both approaches
fig, axes = plt.subplots(1, 2, figsize=(10, 4.5), sharex=True, sharey=True)
for ax, col, title, err in [
    (axes[0], "pmv_linear", "Linear estimate (original MATLAB)", rep.mae_linear),
    (axes[1], "pmv_ml", "ML surrogate (gradient boosting)", rep.mae_ml),
]:
    ax.scatter(test["pmv"], test[col], s=3, alpha=0.3, color="#2a6fdb")
    ax.plot([-3, 3], [-3, 3], color="#d1495b", lw=1.2, label="perfect")
    ax.set_xlim(-3, 3)
    ax.set_ylim(-3, 3)
    ax.set_title(f"{title}\nMAE = {err:.3f} PMV")
    ax.set_xlabel("Exact ISO 7730 PMV")
    ax.grid(alpha=0.3)
axes[0].set_ylabel("Predicted PMV")
axes[0].legend(loc="upper left")
fig.tight_layout()
fig.savefig(REPO / "docs" / "images" / "pmv_surrogate.png", dpi=150)
print("saved figure")
