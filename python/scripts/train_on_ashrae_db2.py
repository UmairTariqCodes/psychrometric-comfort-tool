"""Stage 2: learn thermal comfort from real occupants and compare with PMV.

1. Download the free ASHRAE Global Thermal Comfort Database II CSV
   (https://doi.org/10.6078/D1F671) into python/data/.
2. Run:  python scripts/train_on_ashrae_db2.py data/<file>.csv

Prints how well an ML model and the ISO 7730 PMV each predict the
thermal-sensation votes of real people on a held-out 20 % test set.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from psychro.ml import compare_ml_vs_pmv, load_ashrae_db2  # noqa: E402

if len(sys.argv) != 2:
    sys.exit(__doc__)

df = load_ashrae_db2(sys.argv[1])
print(f"Loaded {len(df):,} usable votes")
res = compare_ml_vs_pmv(df)
res.pop("model")
(ROOT / "results").mkdir(exist_ok=True)
(ROOT / "results" / "db2_metrics.json").write_text(json.dumps(res, indent=2))
print(json.dumps(res, indent=2))
