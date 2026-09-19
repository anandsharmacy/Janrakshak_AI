# Inference image for the corridor disruption model.
#
#   docker build -f deploy/Dockerfile -t sih-infer:final_v3 .
#   docker run -p 8080:8080 -v $PWD/deploy/featurestore:/data/featurestore:ro \
#              -v $PWD/deploy/scores:/data/scores sih-infer:final_v3
#
# NOT BUILT OR RUN in Stage 11 — no Docker on the benchmark machine. Everything the
# image runs WAS exercised in an identical venv built from deploy/requirements.txt
# (Python 3.12, no scikit-learn, no geopandas); see DEPLOYMENT.md §6.
#
# The model bundle is baked into the image (immutable, one image = one model
# version). The feature store and the scores are volumes: they change daily and are
# written by the batch job, not by the API.
FROM python:3.12-slim

# LightGBM's wheel needs the OpenMP runtime
RUN apt-get update \
 && apt-get install -y --no-install-recommends libgomp1 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY deploy/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY src/sih_ml /app/src/sih_ml
COPY conf /app/conf
COPY deploy/gunicorn.conf.py /app/deploy/gunicorn.conf.py
COPY deploy/bundles/final_v3 /models/bundle

ENV PYTHONPATH=/app/src \
    PYTHONUNBUFFERED=1 \
    SIH_BUNDLE=/models/bundle \
    SIH_STORE=/data/featurestore \
    SIH_SCORES=/data/scores \
    SIH_THREADS=1 \
    SIH_WORKERS=4

RUN useradd --uid 10001 --no-create-home sih
USER 10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request,sys; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2)" || exit 1

CMD ["gunicorn", "-c", "/app/deploy/gunicorn.conf.py", "sih_ml.serve.api:create_app()"]
