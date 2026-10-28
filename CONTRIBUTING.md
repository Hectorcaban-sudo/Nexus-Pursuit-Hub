# Contributing

1. Read the [developer guide](docs/guides/developer-guide.md).
2. Branch from `main`: `feature/NXP-123-short-name` or `fix/NXP-456-short-name`.
3. Follow the conventions: `NXP_` prefix (LWC `nxp`), API 68.0, user mode for anything users see, configuration in custom metadata.
4. Add or update tests. Apex coverage must be at least 85% per package. Add a Jest test for new LWCs.
5. Run `scripts/validate.sh --org <your-org>` and paste the summary into the PR.
6. Commit with Conventional Commits (`feat(search): add back-test chart`, `fix(push): …`).
7. Open a PR with one story, ideally under ~400 changed lines. One reviewer from CODEOWNERS approves.
8. If you change a pattern or a decision, add an ADR in `docs/adr/`. If you change a flow, update its diagram in `docs/diagrams/src` and run `render.sh`.
