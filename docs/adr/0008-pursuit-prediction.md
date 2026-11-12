# ADR 0008: Likely to Pursue is a small explainable model trained in Apex

- Status: Proposed (feature branch)
- Date: 2026-11-12

## Context

BD wants a prediction of which notices are worth their time, beyond the rule-based fit score. Einstein Discovery, Data Cloud and Model Builder may not be licensed or approved in our Government Cloud org, and a predictor has to explain itself the way fit reasons do.

## Decision

Predict whether BD will **pursue** a notice (push it rather than dismiss it), not whether we would win. Learn from decisions already recorded in Nexus with a naive Bayes model over a few categorical factors, trained nightly in batch Apex. Store each trained model with its decision counts and a hold-out accuracy (AUC on the newest 20% of decisions), show the likelihood next to the fit score with the factors that moved it most, and keep it off until there are enough decisions.

## Consequences

It runs anywhere Nexus runs, sends no data outside Salesforce, and every score can be explained by counts users recognise. It is simpler than a trained ML model and learns past habits, so it is shown beside the fit score and labelled as not a win probability. If Einstein Discovery becomes available, a model there can write the same fields and replace the Apex trainer without changing the screens.
