PY := ../data2/other_files/venv/bin/python
export PYTHONPATH := src
export PYTHONWARNINGS := ignore

.PHONY: stage2 labels panel splits qa gate test clean stage3 stage4 stage4-clean stage5 stage6 stage6-fresh stage7 stage7-final-test stage8 stage9 stage10 deploy-venv bundle score serve-dev serve bench mlflow-ui publish-venv publish-segments publish publish-current test-publish
export DYLD_LIBRARY_PATH := /opt/homebrew/opt/libomp/lib

stage2: ## run the full Stage 2 pipeline
	$(PY) scripts/run_stage2.py

labels:
	$(PY) -m sih_ml.labels.build_labels

panel:
	$(PY) -m sih_ml.features.build_panel

splits:
	$(PY) -m sih_ml.splits.make_splits

qa:
	$(PY) -m sih_ml.labels.qa

gate: ## evaluate the Stage 2 exit gate
	$(PY) scripts/stage2_gate.py

stage3: ## train + evaluate the baseline model (needs libomp: brew install libomp)
	$(PY) scripts/run_stage3.py

stage4: ## train from scratch with tracking/checkpointing (auto-resumes if interrupted)
	MLFLOW_DISABLE_AGENT_HINT=1 $(PY) scripts/run_stage4.py

stage4-clean: ## discard checkpoints so the next stage4 run starts fresh
	rm -rf checkpoints/
	@echo "checkpoints cleared — next 'make stage4' starts from scratch"

stage5: ## evaluation + error analysis on held-out data (does NOT touch final_test)
	$(PY) scripts/run_stage5.py

stage6: ## fine-tuning + HPO (resumes an existing Optuna study)
	MLFLOW_DISABLE_AGENT_HINT=1 $(PY) scripts/run_stage6.py

stage6-fresh: ## discard the Optuna study and search from scratch
	rm -rf studies/
	@echo "study cleared - next 'make stage6' starts a new search"

stage7: ## accuracy optimization — arm ladder, ensemble, calibration, thresholds
	$(PY) scripts/run_stage7.py

stage7-final-test: ## OPEN THE LOCKED TEST SET (once, needs reports/stage7/PREREGISTRATION.json)
	$(PY) scripts/open_final_test.py

stage8: ## final model validation — reproducibility, robustness, readiness (selects nothing)
	$(PY) scripts/run_stage8.py

mlflow-ui: ## browse the experiment history
	$(PY) -m mlflow ui --backend-store-uri sqlite:///mlruns/mlflow.db

test:
	$(PY) -m pytest tests/ -q

clean: ## drop derived artifacts (keeps interim cache + sources.lock.json)
	rm -f data/processed/*.parquet data/processed/manifests/labels_v1.json \
	      data/processed/manifests/panel_v1.json data/processed/manifests/folds_v1.json \
	      reports/*.md reports/*.png reports/*.csv

stage9: ## remediation of the Stage 8 findings (leak, confound, monotonicity, steep terrain)
	$(PY) scripts/run_stage9.py

stage10: ## one continuous-improvement campaign (dev only; appends to the experiment ledger)
	$(PY) scripts/run_stage10.py

# ---- Stage 11: deployment ----------------------------------------------------
DATE ?= 2025-08-15
DEPLOY_PY ?= .venv-deploy/bin/python

deploy-venv: ## minimal serving env from deploy/requirements.txt (Python 3.12, no sklearn)
	uv venv -p 3.12 .venv-deploy && uv pip install -p .venv-deploy/bin/python -r deploy/requirements.txt

bundle: ## export the registry champion -> deploy/bundles/<version> + feature store
	$(PY) -m sih_ml.serve.build

score: ## score the corridor for DATE (exit 3 = rainfall for DATE not available yet)
	$(DEPLOY_PY) -m sih_ml.serve.batch --date $(DATE)

serve-dev: ## local API on :8080 (stdlib server; dev only)
	$(DEPLOY_PY) -m sih_ml.serve.api

serve: ## production API (gunicorn, deploy/gunicorn.conf.py)
	$(dir $(DEPLOY_PY))gunicorn -c deploy/gunicorn.conf.py 'sih_ml.serve.api:create_app()'

bench: ## accuracy of compression variants + pipeline cost -> reports/stage11/
	$(PY) -m sih_ml.serve.benchmark

# ---- ML integration: publish scored days to Supabase (ML_INTEGRATION_PLAN.md) ----
PUBLISH_PY ?= .venv-publish/bin/python
MODE ?= live
SIH_PUBLISH_DSN ?= postgresql://postgres:postgres@127.0.0.1:54322/postgres
export SIH_PUBLISH_DSN

publish-venv: ## serving deps + psycopg (+ pytest for test-publish)
	uv venv -p 3.12 .venv-publish && uv pip install -p .venv-publish/bin/python -r deploy/requirements-publish.txt pytest

publish-segments: ## load segment centroids + coverage into Supabase (once per feature-store build)
	$(PUBLISH_PY) -m sih_ml.serve.publish segments

publish: ## publish DATE to Supabase; MODE=replay for historical days (e.g. make publish DATE=2025-08-05 MODE=replay)
	$(PUBLISH_PY) -m sih_ml.serve.publish run --date $(DATE) --mode $(MODE)

publish-current: ## re-point the apps at an already published DATE (replay switch / rollback)
	$(PUBLISH_PY) -m sih_ml.serve.publish current --date $(DATE)

test-publish: ## publisher tests; database tests run in a rolled-back transaction
	SIH_TEST_DSN=$(SIH_PUBLISH_DSN) $(PUBLISH_PY) -m pytest tests/test_publish.py -q
