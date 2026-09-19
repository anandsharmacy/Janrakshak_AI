"""Stage 7 — accuracy optimization.

Every optimization is expressed as an *arm*: a pure transform of a fold's
TRAINING rows only. The early-stopping rows and the held-out fold are never
touched, which is what keeps the comparison honest (see harness.py).
"""
