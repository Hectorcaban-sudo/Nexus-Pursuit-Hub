# data

| Folder      | Contents                                                                                                                             | Used by                                                          |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------- |
| `seed/`     | Sample agencies, company profile, contract vehicles and 10 **sample** notices (all marked `SAMPLE`) as an `sf data import tree` plan | `scripts/dev-setup.sh`, demos                                    |
| `fixtures/` | Recorded API response shapes (SAM.gov opportunities page, USAspending award page) and an example Apex REST request                   | Apex tests (inline copies), API docs, manual testing with `curl` |

Load the seed data into an org:

```bash
sf data import tree --plan data/seed/plan.json --target-org nxp-dev
```

Seed data is for development and demo orgs only. Never load it into UAT or production.
