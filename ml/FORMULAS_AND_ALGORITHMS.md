# Formulas and Algorithms Used to Train the Model

This document records the formulas and algorithms implemented in the `sih-ml`
training pipeline. It distinguishes the baseline/final training path from
algorithms that are implemented as optimization or diagnostic arms.

The prediction task is binary classification of a road segment on a day:

\[
y \in \{0,1\}, \qquad
y=1 \text{ means a rainfall-triggered disruption is labelled for that segment-day.}
\]

The primary model is LightGBM gradient-boosted decision trees. The primary
evaluation is average precision (AP) under five spatial-block folds.

## 1. Label and sample-weight construction

### Positive labels

Events are filtered by date, hazard type, trigger, and location accuracy, then
deduplicated when they are within the configured temporal and spatial windows.
An event is snapped to candidate road segments. For a candidate at distance
`d` from an event whose location accuracy radius is `r`, the distance-decay
factor is

\[
d_{\mathrm{decay}} = \exp\left(-\frac{d}{r}\right),
\qquad r=\max(\text{event accuracy}, 500\text{ m}).
\]

For landslides, a susceptibility factor is also applied when the candidate is
more than 100 m from the source:

\[
s_{\mathrm{factor}} = 0.5 + q_{\mathrm{susceptibility}},
\]

where the susceptibility quantile is in approximately `[0, 1]`. The resulting
label confidence is capped at one:

\[
c = \min\left(1,
    c_{\mathrm{tier}} d_{\mathrm{decay}} s_{\mathrm{factor}}\right).
\]

Persistence-day labels use an additional factor of `1.0` on the event day and
`0.8` on subsequent persistence days. If multiple labels collapse to the same
`(segment_id, date)`, the best tier and then the highest confidence are kept.

Negative examples are case-control samples at the configured negative:positive
ratio. The negative pool contains:

- easy negatives: low susceptibility and farther than the hazard-exclusion
  radius from known events;
- hard negatives: outside the exclusion radius but within the configured event
  donut, with susceptibility matched to positives.

Negative dates are sampled using a configured monsoon fraction and otherwise
uniformly over the observed years. Negative rows that collide with positive
segment-days are removed.

### Training sample weights

The panel stores:

\[
w_i = \operatorname{clip}(c_i, 0.05, 1.0),
\]

where `c_i` is label confidence. These weights are passed into LightGBM for
the built-in binary objective and are explicitly applied inside the custom
focal objective.

The optional weighting arms transform the base weights as follows, then
rescale them to preserve the original mean weight:

\[
w_i' = \begin{cases}
1 & \text{uniform}\\
\sqrt{\max(w_i,0)} & \text{sqrt}\\
\max(w_i,0)^2 & \text{square}.
\end{cases}
\]

For any transformed weights, the mass-preserving rescale is

\[
w_i'' = w_i'\frac{\operatorname{mean}(w)}{\operatorname{mean}(w')}.
\]

## 2. Feature engineering

All rainfall features use only observations on or before

\[
t_{\mathrm{cutoff}} = t_{\mathrm{event}} - 1\text{ day},
\]

which prevents next-day information from entering the features.

### Rainfall accumulation windows

For each rainfall window \(W\in\{1,3,7,15,30\}\), the feature is the sum of
daily CHIRPS precipitation in the preceding `W` days:

\[
R_W(t) = \sum_{k=0}^{W-1} P(t-k).
\]

The implementation evaluates these sums with a per-cell cumulative sum. It
also creates the maximum one-day rainfall in the preceding three days:

\[
R_{\max,3}(t) = \max\{P(t),P(t-1),P(t-2)\}.
\]

### Antecedent precipitation index

The 30-day antecedent precipitation index uses exponential decay:

\[
\operatorname{API}_{30}(t) = \sum_{k=0}^{29} P(t-k)\,0.92^k.
\]

The implementation also records the number of days since the most recent day
with more than 1 mm of rainfall, looking back up to 60 days. If no such day is
found, the value is 60.

### Intensity-duration threshold features

For a window of `D` days, observed average intensity and the configured
regional threshold are:

\[
I_{\mathrm{obs}} = \frac{R_D}{24D},
\qquad
I_{\mathrm{thr}} = 5.8294(24D)^{-0.4141}.
\]

The intensity-duration ratio and exceedance flag are:

\[
\operatorname{IDRatio}_D = \frac{I_{\mathrm{obs}}}{I_{\mathrm{thr}}},
\qquad
\operatorname{IDExceed}_D = \mathbf{1}[\operatorname{IDRatio}_D > 1].
\]

These are computed for `D` equal to 1, 3, and 7 days.

### Cyclic and circular features

Aspect is represented without a discontinuity at north:

\[
\operatorname{aspect\_sin}=\sin(\theta),
\qquad
\operatorname{aspect\_cos}=\cos(\theta),
\]

where \(\theta\) is aspect in radians. Day-of-year is encoded similarly:

\[
\operatorname{doy\_sin}=\sin\left(\frac{2\pi\,\operatorname{dayofyear}}{365.25}\right),
\qquad
\operatorname{doy\_cos}=\cos\left(\frac{2\pi\,\operatorname{dayofyear}}{365.25}\right).
\]

`is_monsoon` is one for June through September and zero otherwise.

Static terrain, soil, hydrology, and road attributes are joined by segment.
Soil all-zero vectors are treated as missing and represented by a missingness
flag plus NaNs. High-cardinality identifiers and metadata are excluded from the
model. Event-history count features are excluded from the spatial-CV baseline
because they can reveal held-out event history.

## 3. Preprocessing

### Tree model

The tree pipeline preserves numeric NaNs for LightGBM's native missing-value
handling. Numeric columns are coerced to numeric. Categorical columns are
converted to strings, missing values become `__missing__`, and the result is a
pandas categorical dtype.

### Linear comparison model

The logistic baseline uses a separate pipeline:

- numeric and cyclic columns: median imputation, then standardization;
- flags: most-frequent imputation;
- categoricals: constant `__missing__` imputation and one-hot encoding;
- categories occurring fewer than 20 times are grouped by the encoder's
  `min_frequency` setting.

Every learned preprocessing transform is fit only on the training portion of a
fold and then applied to early-stopping, validation, and test rows.

## 4. Data splitting and leakage controls

### Development and locked test sets

The locked `final_test` rows are excluded from all model selection and cross-
validation. The final test is opened only after a preregistration file freezes
the configuration and metric list.

### Spatial cross-validation

The primary evaluation uses five spatial-block folds. For each fold:

1. validation rows are the held-out spatial block;
2. training rows are the remaining development rows;
3. a 5 km buffer around the validation block is removed from training;
4. an inner split selects the tree count for early stopping.

This keeps nearby road segments from appearing on both sides of the outer
evaluation boundary.

### Event-grouped early stopping

For the current configuration, positive rows are assigned to the inner
early-stopping set by whole `event_id` groups. Negative rows are sampled at the
same configured fraction. This prevents sibling segment-days from the same
event appearing in both fitting and early-stopping data. The older random-row
split remains available only for reproducing earlier stages.

### Inner cross-fitted mining

Hard-example mining trains small prospector models inside each outer training
fold. Each row receives a score only from an inner model that did not train on
that row. Positive event rows are grouped together in the inner split, and
negative rows are randomly assigned to inner folds. This avoids using outer
validation labels to choose training weights.

## 5. Primary model: LightGBM gradient boosting

The production model is a LightGBM binary gradient-boosted tree ensemble:

\[
F_M(x) = F_0(x) + \sum_{m=1}^{M}\eta f_m(x),
\]

where \(f_m\) is a decision tree, \(\eta\) is the learning rate, and `M` is
bounded by `n_estimators` and selected by early stopping.

For the built-in binary objective, the model uses the weighted binary
log-loss:

\[
\mathcal{L}_{\mathrm{log}} =
-\sum_i w_i\left[y_i\log(p_i)+(1-y_i)\log(1-p_i)\right],
\qquad p_i=\sigma(F(x_i)),
\]

with sigmoid

\[
\sigma(z)=\frac{1}{1+e^{-z}}.
\]

LightGBM fits each next tree from the first- and second-order derivatives of
the objective. The configured tree regularization and sampling controls are:

- leaf count and maximum depth constraints;
- minimum child sample count and minimum split gain;
- row subsampling (`subsample`) at the configured frequency;
- feature subsampling (`colsample_bytree`);
- L1 and L2 leaf regularization;
- deterministic row-wise training and fixed per-fold seeds.

The configured Stage 7 starting values are recorded in
`conf/optimize_config.yaml`; the final frozen values are copied into
`reports/stage7/PREREGISTRATION.json` when the optimization stage completes.

### Class imbalance

For the built-in objective, the per-fold positive scale is

\[
\operatorname{scale\_pos\_weight}
=\frac{N_{\mathrm{negative}}}{\max(1,N_{\mathrm{positive}})}
\times m,
\]

where `m` is the configured `scale_pos_weight_mult`. This is separate from
the confidence sample weights \(w_i\).

### Monotonicity constraints

Configured rainfall features receive an increasing monotonicity constraint:

\[
x_j \le x_j' \Longrightarrow F(x) \le F(x')
\]

when all other features are held fixed. Features without a configured
constraint receive zero in LightGBM's monotone constraint vector.

### Early stopping

The custom `pr_auc` evaluation metric is average precision on the early-
stopping set. Training stops after the configured number of rounds without an
improvement. When `early_stopping_metric` is `pr_auc`, the built-in metric is
disabled so PR-AUC is the sole stopping signal.

## 6. Optional focal-loss objective

The optimization pipeline implements binary focal loss as an alternative to
weighted binary log-loss. With `p=sigmoid(z)`,

\[
p_t = yp+(1-y)(1-p),
\qquad
\alpha_t = \alpha y+(1-\alpha)(1-y),
\]

\[
\mathcal{L}_{\mathrm{focal}}
=-\alpha_t(1-p_t)^\gamma\log(p_t).
\]

The analytic gradient with respect to the raw margin is computed as:

\[
\frac{\partial L}{\partial z}
=\alpha_t\left[\gamma(1-p_t)^{\gamma-1}\log(p_t)
-\frac{(1-p_t)^\gamma}{p_t}\right]
(2y-1)p(1-p).
\]

The Hessian supplied to LightGBM is a central finite difference of that
gradient:

\[
h(z)\approx\frac{g(z+\varepsilon)-g(z-\varepsilon)}{2\varepsilon},
\qquad \varepsilon=10^{-5},
\]

then clipped to at least \(10^{-6}\). Sample weights multiply both gradient
and Hessian. `scale_pos_weight` is not used with this objective; class balance
is represented by focal `alpha` instead.

Because LightGBM returns raw margins for a custom objective, prediction applies
the sigmoid before calibration or thresholding.

## 7. Optimization algorithms and training transforms

These algorithms are implemented as Stage 7 candidate arms. They are evaluated
on training rows only and are included in the final recipe only if selected by
the frozen optimization result.

### Exact feature-vector deduplication

Within a training fold, exact duplicate feature vectors are hashed and only the
first row in each duplicate group is retained.

### Confidence filtering

An arm can drop positive rows below a confidence floor while retaining every
negative row:

\[
\operatorname{keep}_i = (y_i=0)\lor(c_i\ge c_{\min}).
\]

### Model-difficulty mining

Let \(r_i\in[0,1]\) be the percentile rank of an inner out-of-fold score.
Hard-negative mining uses

\[
w_i' = w_i(1+\alpha r_i), \quad y_i=0,
\]

and hard-positive mining uses

\[
w_i' = w_i\left(1+\alpha(1-r_i)\right), \quad y_i=1.
\]

The modified class weights are mass-preserved using the rescale formula above.
An easy-negative arm drops the lowest-scoring negative fraction.

### Rainfall jitter

For each training row, one coherent multiplicative rainfall factor is sampled:

\[
f\sim\operatorname{LogNormal}(0,\sigma^2).
\]

All rainfall windows, API, and intensity-duration ratios are multiplied by
`f`; exceedance flags are recomputed, while dates, terrain, and categories stay
fixed. An append variant retains both original and jittered rows.

### Gaussian noise

The contrast augmentation adds independent noise to selected numeric columns:

\[
x_j' = x_j + \epsilon_j,
\qquad
\epsilon_j\sim\mathcal{N}(0,(\sigma\,s_j)^2),
\]

where \(s_j\) is the observed standard deviation of column `j`. Arms cover all
numeric columns, terrain-only columns, and rainfall-only columns.

### Spatially restricted SMOTE

For two positive rows `i` and `j` from the same spatial block, a synthetic
numeric vector is:

\[
x_{\mathrm{new}} = x_i+\lambda(x_j-x_i),
\qquad \lambda\sim U(0,1).
\]

Categorical values come from the seed row. The synthetic sample weight is the
parent mean:

\[
w_{\mathrm{new}}=\frac{w_i+w_j}{2}.
\]

Restricting donors to a spatial block prevents interpolation between unrelated
geographies.

## 8. Hyperparameter search and arm comparison

The HPO stage uses Optuna to maximize mean AP over selection folds. Its default
sampler is multivariate TPE; the alternative is random search. The default
pruner is a median pruner with a startup-trial and warmup period; the
alternative is no pruning. Intermediate mean AP after each fold is reported to
the pruner.

Stage 7 candidate arms use paired fold deltas against a fixed bar:

\[
d_f=AP_{\mathrm{arm},f}-AP_{\mathrm{bar},f},
\qquad
\bar d=\frac{1}{K}\sum_{f=1}^{K}d_f.
\]

Sign-flip permutation testing evaluates the null distribution by multiplying
each paired delta by an independently chosen sign. When \(2^K\le n_{\mathrm{permutations}}\), every sign pattern is enumerated exactly; otherwise,
the configured number of random sign patterns is sampled. The two-sided
p-value is

\[
p=\frac{1}{B}\sum_{b=1}^{B}
\mathbf{1}\left[|\bar d_b|\ge |\bar d|\right].
\]

An arm is considered an improvement only when it has a positive mean delta,
improves the configured minimum number of folds, and clears the configured
alpha level. Leading arms are replicated with fresh seeds.

Ensemble candidates use leave-one-fold-out weight selection so a fold's blend
weight is never fitted on that fold. The evaluated ensemble prediction is a
weighted combination of member scores:

\[
p_{\mathrm{blend}}=\sum_{m=1}^{M}\beta_m p_m,
\qquad \beta_m\ge0,\quad\sum_m\beta_m=1.
\]

## 9. Probability calibration

Calibration is fitted on development out-of-fold predictions, never on the
final model's in-sample predictions.

### Isotonic calibration

The isotonic calibrator learns a nondecreasing function \(g\) that maps raw
scores to probabilities:

\[
q=g(p),
\qquad g(p_1)\le g(p_2)\text{ when }p_1\le p_2.
\]

Out-of-range values are clipped. A logistic calibrator is also implemented as a
fallback/comparison method by fitting logistic regression to the raw log-odds
`logit(p)`.

### Prior correction

When a target deployment prior is configured, calibrated odds are shifted from
the training prior to the target prior:

\[
q'=\sigma\left(
\operatorname{logit}(q)+
\operatorname{logit}(\pi_{\mathrm{target}})-
\operatorname{logit}(\pi_{\mathrm{train}})
\right).
\]

Calibration can be pooled or fitted separately by slope stratum. Thin strata
fall back to the pooled calibrator.

## 10. Threshold selection and reported metrics

The model is primarily a ranking model, so AP is reported before selecting an
operating threshold.

For a threshold \(\tau\),

\[
\hat y_i=\mathbf{1}[p_i\ge\tau].
\]

Precision, recall, and F1 are:

\[
\operatorname{precision}=\frac{TP}{TP+FP},
\qquad
\operatorname{recall}=\frac{TP}{TP+FN},
\]

\[
F_1=\frac{2\,\operatorname{precision}\,\operatorname{recall}}
{\operatorname{precision}+\operatorname{recall}}.
\]

The cost-based threshold minimizes:

\[
C(\tau)=c_{FN}FN(\tau)+c_{FP}FP(\tau),
\]

with `c_FN / c_FP` swept over the configured policy values. The F-beta
alternative maximizes:

\[
F_\beta=\frac{(1+\beta^2)PR}{\beta^2P+R}.
\]

The pipeline reports AP, ROC-AUC, Brier score, expected calibration error,
precision/recall at fixed `k`, lift at fixed top fractions, confusion metrics,
and terrain-stratified diagnostics.

The Brier score is

\[
\operatorname{Brier}=\frac{1}{n}\sum_i(p_i-y_i)^2.
\]

For `B` populated probability bins, expected calibration error is

\[
\operatorname{ECE}=\sum_{b=1}^{B}\frac{|S_b|}{n}
\left|\operatorname{mean}_{i\in S_b}(p_i)-
\operatorname{mean}_{i\in S_b}(y_i)\right|.
\]

## 11. Final fit and inference contract

After configuration freeze, the final model is fit using the frozen recipe on
all development rows, with an inner early-stopping split used only to choose
the tree count. The locked test is then scored once. Its raw scores are passed
through the calibrator fitted on development OOF scores, followed by the frozen
operating threshold for binary alerts.

The intended use is risk ranking of road segments per day and a routing-edge
penalty. The score is not a standalone closure decision.

## Implementation index

- Feature formulas: `src/sih_ml/features/rainfall.py` and
  `src/sih_ml/features/build_panel.py`
- Labels and base weights: `src/sih_ml/labels/build_labels.py`
- Feature schema and fold-local preprocessing:
  `conf/feature_spec.yaml` and `src/sih_ml/preprocess/transformers.py`
- Splits and early stopping: `src/sih_ml/models/dataset.py` and
  `src/sih_ml/train/cv.py`
- LightGBM model and prediction conversion:
  `src/sih_ml/models/lgbm_baseline.py`
- Focal objective and augmentation: `src/sih_ml/optimize/losses.py` and
  `src/sih_ml/optimize/augment.py`
- Optimization and arm comparison: `src/sih_ml/optimize/data_opt.py`,
  `src/sih_ml/optimize/harness.py`, and `src/sih_ml/train/hpo.py`
- Calibration, thresholding, and metrics:
  `src/sih_ml/models/calibration.py`, `src/sih_ml/optimize/calibrate.py`,
  `src/sih_ml/optimize/threshold.py`, and `src/sih_ml/eval/metrics.py`
- Frozen final fit: `src/sih_ml/train/final_test.py`