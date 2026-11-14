# ADR 0009: Price-to-Win is statistics over award history, not AI or a win model

- Status: Proposed (branch `feature/price-to-win`)
- Date: 2026-11-13

## Context

Users asked for a price-to-win view like commercial capture tools: what past awards for this kind of work were worth, whether incumbents keep their work, and where a bid should land. Nexus already stores USAspending award summaries (vendor, agency, obligated amount, period) and each notice's predecessor award.

Public award data records only the winning award. It has no losing bids, no losing prices and no reasons for a loss.

## Decision

- The panel is computed in Apex (`NXP_PriceToWinService`) from `NXP_Award_Summary__c`: per-year values (obligated ÷ years run, at least one), low / quartiles / median / high per scope, the predecessor contract, and an incumbent-hold estimate from follow-on matching. Same input, same numbers; no AI calls, so it doesn't use the daily AI limit.
- A nearest-neighbour estimate (similarity-weighted median of the 20 most similar awards by NAICS, agency, PSC, title words and recency) covers notices whose scope has too few awards. It explains itself by listing the awards it used.
- The panel shows where a price sits among past awards. It does not show a probability of winning, because the data to learn one does not exist in public sources.
- The USAspending connector stores NAICS and PSC on awards so the comparisons can filter on them.

## Consequences

- Figures are reproducible and traceable to award records, and cost nothing to run.
- Comparisons are only as good as the award history loaded; orgs need the USAspending feed with enough look-back.
- A real win model needs our own outcomes. A later step can record the bid price and won/lost on the Opportunity, save where that price sat in the range, and train a model (like the pursuit prediction) once enough decisions exist.
- The assistant and Analyze this notice can reuse the service later (an action and facts), without extra AI calls for the numbers.
