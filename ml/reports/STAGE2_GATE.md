# Stage 2 exit gate

## ✅ PASS — cleared to start Stage 3 modelling

| check | result |
|---|---|
| leakage/schema/split tests green | ✅ |
| positive clusters >= 20 | ✅ |
| neg:pos ratio in [8, 12] | ✅ |
| every panel row has a spatial fold | ✅ |
| every spatial fold has >=1 positive val row | ✅ |
| each block in exactly one fold | ✅ |
| gold rows are all in final_test | ✅ |
| soil nodata -> NaN | ✅ |
| no duplicate segment-days in panel | ✅ |
| sources.lock.json present | ✅ |
| all manifests written | ✅ |

## Context
- positive segment-days: 9387
- positive clusters (LOECO groups): 115
- distinct positive segments: 2011
- verified (gold) rows: 3
- spatial blocks / with positives: 114 / 31
- final_test rows / positives: 40272 / 1572

Primary metric for Stage 3: **precision@k / average precision under spatial-block CV and LOECO**, with the out-of-time split reported separately as the pessimistic bound. See DATA_DECISIONS.md.