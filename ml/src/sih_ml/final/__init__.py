"""Stage 8 — final model validation.

Stage 8 does NOT select a model and does NOT re-decide anything. The locked test
set was opened once, under pre-registration, at the end of Stage 7; that opening is
the project's single unbiased estimate. Everything here is descriptive analysis of
a frozen artifact: the config hash is verified against `PREREGISTRATION.json` on
entry, and any mismatch aborts the run.
"""
