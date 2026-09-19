# Stage 7 — Accuracy Optimization results

git `nogit` · folds [0, 1, 2, 3, 4] · **`final_test` not opened by this run.**

Protocol: every arm runs on the SAME 5 spatial folds with the SAME seeds and early-stopping splits, and is compared to the bar by **paired per-fold deltas** with a sign-flip permutation test. With 5 folds the smallest attainable two-sided p is 0.0625, so the test can reject noise but cannot certify a small effect — it is reported, not leaned on.

**The bar** (Stage 6 selected config): mean AP **0.3506 ± 0.1607** over folds 0:0.507, 1:0.582, 2:0.230, 3:0.195, 4:0.238

## Every arm, ranked by measured delta

| arm | mean AP | delta | p | folds+ | verdict |
|--|--|--|--|--|--|
| `aug/gaussian_all_s0.4` | 0.3835 | **+0.0330** | 0.375 | 3/5 | not demonstrated |
| `loss/focal_g1.5` | 0.3812 | **+0.0307** | 0.125 | 4/5 | not demonstrated |
| `loss/focal_g2.0` | 0.3812 | **+0.0307** | 0.125 | 4/5 | not demonstrated |
| `aug/gaussian_all_s0.2` | 0.3793 | **+0.0288** | 0.125 | 4/5 | not demonstrated |
| `aug/gaussian_all_s0.1` | 0.3787 | **+0.0282** | 0.062 | 5/5 | improvement |
| `aug/gaussian_terrain_only_s0.1` | 0.3757 | **+0.0252** | 0.500 | 2/5 | not demonstrated |
| `aug/smote_k5_f0.5` | 0.3678 | **+0.0173** | 0.062 | 5/5 | improvement |
| `aug/gaussian_all_s0.05` | 0.3631 | **+0.0125** | 0.188 | 4/5 | not demonstrated |
| `data/easy_neg_drop_0.3` | 0.3597 | **+0.0092** | 0.125 | 4/5 | not demonstrated |
| `data/conf_floor_0.25` | 0.3563 | **+0.0057** | 0.875 | 2/5 | not demonstrated |
| `data/weight_uniform` | 0.3556 | **+0.0050** | 0.750 | 2/5 | not demonstrated |
| `data/weight_sqrt` | 0.3547 | **+0.0042** | 0.312 | 4/5 | not demonstrated |
| `data/hard_neg_a3.0` | 0.3547 | **+0.0041** | 0.438 | 3/5 | not demonstrated |
| `aug/gaussian_rain_only_s0.1` | 0.3536 | **+0.0031** | 0.375 | 4/5 | not demonstrated |
| `aug/rain_jitter_s0.1` | 0.3535 | **+0.0029** | 0.688 | 4/5 | not demonstrated |
| `data/hard_neg_a1.0` | 0.3519 | **+0.0013** | 0.812 | 4/5 | not demonstrated |
| `loss/focal_g3.0` | 0.3506 | **+0.0000** | 1.000 | 4/5 | not demonstrated |
| `loss/focal_g1.0` | 0.3503 | **-0.0003** | 1.000 | 4/5 | not demonstrated |
| `data/weight_square` | 0.3502 | **-0.0003** | 1.000 | 2/5 | not demonstrated |
| `data/dedup` | 0.3487 | **-0.0019** | 0.562 | 1/5 | not demonstrated |
| `data/conf_floor_0.35` | 0.3486 | **-0.0020** | 0.938 | 2/5 | not demonstrated |
| `data/hard_pos_a1.0` | 0.3419 | **-0.0087** | 0.375 | 2/5 | not demonstrated |
| `aug/rain_jitter_append_s0.25` | 0.3390 | **-0.0115** | 0.188 | 1/5 | not demonstrated |
| `aug/rain_jitter_s0.25` | 0.3381 | **-0.0124** | 0.375 | 2/5 | not demonstrated |
| `aug/rain_jitter_s0.5` | 0.3327 | **-0.0179** | 0.250 | 2/5 | not demonstrated |
| `composite/passed` | 0.3782 | **+0.0276** | 0.062 | 5/5 | improvement |
| `composite/all_positive` | 0.3834 | **+0.0328** | 0.500 | 2/5 | not demonstrated |
| `ensemble` | 0.3732 | **+0.0227** | 0.125 | 4/5 | not demonstrated |

### Multiplicity — read this before believing any single row

25 arms were tested at alpha = 0.1. With 5 folds the sign-flip test bottoms out at **p = 2/2⁵ = 0.0625**, so a Bonferroni-corrected threshold (0.1/25 = 0.0040) is **unreachable by construction** — no arm here can be certified family-wise. At uncorrected alpha, ~2.5 of these arms are expected to 'pass' by chance alone. That is why the leading arms are replicated under fresh seeds below rather than declared winners here.

## Seed replication of the leading arms

A fresh seed redraws the event-grouped early-stopping split and the bagging RNG. An effect that survives is not an artifact of one inner split — it is still not a family-wise-corrected result.

| arm | seed-0 delta | replicate mean delta | fold×seed pairs improved | replicated |
|--|--|--|--|--|
| `aug/gaussian_all_s0.4` | +0.0330 | +0.0334 | 12/20 | YES |
| `loss/focal_g1.5` | +0.0307 | +0.0207 | 16/20 | YES |
| `loss/focal_g2.0` | +0.0307 | +0.0186 | 16/20 | YES |
| `aug/gaussian_all_s0.2` | +0.0288 | +0.0322 | 14/20 | YES |
| `aug/gaussian_all_s0.1` | +0.0282 | +0.0176 | 13/20 | YES |
| `aug/smote_k5_f0.5` | +0.0173 | +0.0147 | 16/20 | YES |


## Ensemble members (solo, same folds)

| member | mean AP |
|--|--|
| lgbm | 0.3782 |
| logistic | 0.3299 |
| rain_x_terrain | 0.1647 |

Consensus blend weights: `{'lgbm': 1.0, 'logistic': 0.0, 'rain_x_terrain': 0.0}`

Weights are chosen leave-one-fold-out, so no fold is scored by a weight fitted on it.

## Terrain-stratified model (Stage 5 §1)

On slope >= 10.0° rows only (43,884 rows in the panel):

| model | mean AP |
|--|--|
| global model, restricted to steep rows | 0.3718 |
| dedicated steep-only model | 0.3687 |

delta **-0.0031** (p=1.000) -> **not demonstrated**

## Calibration (cross-fitted)

| variant | global ECE | Brier | worst TERRAIN stratum | worst REGION stratum |
|--|--|--|--|--|
| uncalibrated | 0.0396 | 0.0684 | **1.16×** | 3.10× |
| global_isotonic | 0.0196 | 0.0686 | **2.71×** | 3.39× |
| per_slope_isotonic | 0.0193 | 0.0696 | **1.32×** | 3.50× |

Selected: **per_slope_isotonic**, on the terrain axis.

Global ECE is not the headline — a global calibrator minimises it by construction. The worst-stratum ratio is what Stage 5 §6 flagged and what the routing penalty `W = dist·(1 + λ·P)` is actually exposed to.

The two axes are separated because only one is fixable at inference: terrain is a property of the row being scored, so a calibrator can condition on it; *which region* is not knowable for a new area, so region miscalibration is a residual limitation to disclose, not a target to optimise. Cross-fitting is also why these numbers are worse than Stage 5's — Stage 5 fitted its calibrator on the rows it then scored.

## Operating point / cost sensitivity

| FN:FP | threshold | precision | recall | F1 | FP rate of negatives |
|--|--|--|--|--|--|
| 5 | 0.1642 | 0.236 | 0.700 | 0.353 | 21.0% |
| 10 | 0.0737 | 0.212 | 0.901 | 0.343 | 31.0% |
| 20 | 0.0567 | 0.206 | 0.911 | 0.335 | 32.6% |
| 50 | 0.0245 | 0.168 | 0.963 | 0.286 | 44.1% |
| F3-optimal | 0.0737 | 0.212 | 0.901 | 0.343 | 31.0% |

Shipped default is FN:FP = 20 (threshold 0.0567, precision 0.206, recall 0.911) — **inherited from Stage 3 and still not validated with MDoNER.** The table is the hand-off.

## Cost

| config | model KB | trees | leaves | µs/row | full corridor |
|--|--|--|--|--|--|
| bar (incumbent) | 594.1 | 1009 | 4036 | 2.619 | 0.81s for 309,042 segments |
| composite/passed (selected) | 709.1 | 1199 | 4796 | 3.375 | 1.04s for 309,042 segments |

## Frozen configuration

`PREREGISTRATION.json` pins the final config hash and the exact metric list **before** any locked-test row is read. Open the test with:

```bash
make stage7-final-test
```
