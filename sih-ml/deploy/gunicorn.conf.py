"""gunicorn settings for the inference API.

    gunicorn -c deploy/gunicorn.conf.py 'sih_ml.serve.api:create_app()'

Sized from reports/stage11/ measurements, not defaults. Workers are processes:
request handlers are short CPU-bound numpy/LightGBM calls, so extra threads buy
nothing under the GIL and processes scale across cores. The worker class is
`gthread` (with one thread) rather than `sync` only because sync workers cannot keep
a connection alive: a pooled client (the routing service) would otherwise open a TCP
connection per request, which measured at >1k req/s exhausted the client's ephemeral
ports (DEPLOYMENT.md §6). `preload_app` loads the
bundle and memory-maps the 106 MB feature store once in the master; forked workers
share those pages copy-on-write. The API never predicts in the master, so no OpenMP
thread pool exists at fork time (LightGBM + fork is only unsafe after OpenMP has
started) — verified under load, see DEPLOYMENT.md §6.
"""
import multiprocessing
import os

bind = os.environ.get("SIH_BIND", "0.0.0.0:8080")
workers = int(os.environ.get("SIH_WORKERS", max(2, multiprocessing.cpu_count() // 2)))
worker_class = "gthread"
threads = int(os.environ.get("SIH_WORKER_THREADS", "1"))
preload_app = True
timeout = 30                    # a /v1/score of 5,000 rows is ~tens of ms; 30 s means hung
graceful_timeout = 30
keepalive = 5
max_requests = 20000            # recycle workers periodically; bounds any slow leak
max_requests_jitter = 2000
accesslog = None                # the app writes one structured JSON line per request
errorlog = "-"
loglevel = os.environ.get("SIH_LOG_LEVEL", "info").lower()
raw_env = [f"SIH_THREADS={os.environ.get('SIH_THREADS', '1')}"]   # 1 LightGBM thread / worker
