# DB-backed public-oracle spike

This fork-local spike distinguishes three different checks that should not be
reported as one result:

1. `mvn test` or `mvn verify`: whether a gold variant compiles and its authored
   tests pass.
2. `test.sh`: the public SCARF smoke check currently shipped beside each
   variant.
3. An evaluator-owned database workflow: whether meaningful state changes and
   queries work.

## Reproduce the negative control

```bash
experiments/db-backed-smoke/audit-public-oracles.sh
```

The script serves only static files. It has no Java application and no
database. At benchmark revision `7c83756671f5297cf3576c813c52aa9fb956867f`,
all 24 public `test.sh` scripts under `persistence` and `whole_applications`
accept this fake. A public HTTP-200 result must therefore not be interpreted as
behavioral or persistence equivalence.

## Reproduce one real database workflow

```bash
experiments/db-backed-smoke/roster-spring-workflow.sh
```

This runs the Spring roster tests against H2, starts the gold application, and
checks league/team/player creation, the player-team relationship, salary and
sport queries, deletion, and the final 404. It is an example of the minimum
shape needed for a SCARF-Mongo L2 stateful oracle.

The scripts require free localhost ports 8080, 8081, 8082, and 9080 for the
negative control, and port 8080 for the roster workflow.
