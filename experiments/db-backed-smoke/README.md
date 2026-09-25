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

The address-book workflow exercises a rendered JSF application rather than a
JSON API:

```bash
experiments/db-backed-smoke/address-book-spring-workflow.sh
```

It creates a fully populated contact, verifies it from an independent browser
session, rejects an invalid email, deletes the valid contact, and verifies from
a third session that neither contact remains. This catches both missing
persistence and missing validation while still treating the public UI as the
system boundary. It starts on port 18080 by default; override the port with
`SCARF_ADDRESS_BOOK_PORT`.

Gate 1 pins those checks as the AMP-owned
`amp-scarf-address-book-l2-v1` oracle tuple:

```bash
experiments/db-backed-smoke/validate-address-book-reference.sh
experiments/db-backed-smoke/address-book-oracle-negative-control.sh
```

The first command emits the JSON `scarf-v1` evidence consumed by the Inspect
adapter. The second proves that an HTTP-200 static fake with no Java application
or database is rejected. The versioned manifest is
`address-book-oracle-v1.json`. This is deliberately a one-task pilot tuple, not
a substitute for the still-unavailable public 1,331-test expert-oracle corpus.

The same oracle can grade a prepared candidate workspace:

```bash
experiments/db-backed-smoke/validate-address-book-workspace.sh \
  --work-dir /absolute/path/to/candidate \
  --framework quarkus
```

The framework selects the evaluator-owned build/deploy adapter; it is never
inferred from agent output. Spring and Quarkus gold variants must both pass the
same five behavior/state cases before an agent treatment is run.

The unmodified public Quarkus Address Book target fails the third case: its
`Contact` entity omits the `NotNull`, `Past`, and `Pattern` constraints present
in the Spring source, so `not-an-email` is persisted. This experiment branch
restores those source-equivalent annotations in the Quarkus fixture and records
the distinction explicitly: the public target is a failing baseline; the
fork-local corrected target is the reference executor's behavior-equivalent
fixture. The evaluator also supports both Mojarra and MyFaces command-submit
protocols, so this result is not an artifact of the JSF implementation.

```bash
experiments/db-backed-smoke/roster-spring-workflow.sh
```

This runs the Spring roster tests against H2, starts the gold application, and
checks league/team/player creation, the player-team relationship, salary and
sport queries, deletion, and the final 404. It is an example of the minimum
shape needed for a SCARF-Mongo L2 stateful oracle.

The second workflow exercises a different framework and UI shape:

```bash
experiments/db-backed-smoke/order-quarkus-workflow.sh
```

It packages and starts the Quarkus gold application, creates an order in H2,
reads it back through the rendered order list, deletes it, and verifies that it
is gone. Run these workflows with JDK 21 to match the benchmark Dockerfiles.

The scripts require free localhost ports 8080, 8081, 8082, and 9080 for the
corpus-wide negative control, port 18080 for the Address Book workflow, port
18081 for its focused negative control, port 8080 for the roster workflow, and
port 8082 for the order workflow.

## Reproduce a whole-application database workflow

```bash
experiments/db-backed-smoke/realworld-spring-workflow.sh
```

This builds the Spring RealWorld gold application in its pinned JDK 11
environment, starts it on port 18083, and checks registration, duplicate-email
and bad-password rejection, login, article persistence, tag relationships,
comment relationships, favorites, and deletion. The Gradle cache defaults to
`/private/tmp/scarf-gradle-home`; override it with `SCARF_GRADLE_DIR`. Override
the port with `SCARF_REALWORLD_PORT`.

The spike deliberately does not grade comment deletion yet. The current gold
Spring implementation returns HTTP 200 for `DELETE /articles/{slug}/comments/{id}`
but a subsequent authenticated read still returns the comment. It also permits
unauthenticated comment reads in its security configuration while the request
currently returns HTTP 500. These are source-oracle decisions to resolve, not
behaviors an experimental evaluator should silently bless.

## Corpus-readiness observations

At benchmark revision `7c83756671f5297cf3576c813c52aa9fb956867f`, and in the
official `v0.1.2` release archive, there are 102 `Dockerfile` and 102 `test.sh`
files but no `Makefile`, `metadata.json`, `smoke.py`, or `smoke/` directory.
That layout cannot be consumed directly by the current CLI validator, which
copies a `Makefile`, `Dockerfile`, and smoke assets before invoking `make test`.
The release asset `benchmark-v0.1.2.tar.gz` used for this audit has SHA-256
`df80f269ec0b751e8e18b4cd90a2435a3c2cf194a240b227b7424584a6e3a9ea`.

The released CLI `scarf 0.1.2` confirms the incompatibility in two ways:

- `scarf bench list --layer persistence` prints an empty table because it
  discovers applications only by finding a `Makefile`.
- `scarf validate` can nevertheless exit 0 and print `Successfully validated`
  against this release. With a candidate-owned `output/test.sh`, GNU Make's
  implicit rule creates an executable `test` by running `cat test.sh >test`
  and `chmod a+x test`; the evaluator script is never executed. The resulting
  metadata is `compile_ok: UNK`, `deploy_ok: UNK`, `tests_passed: null`, with
  failure category `unknown`.

The validator should fail closed before invoking Make when the evaluator source
does not provide its required `Makefile`, `Dockerfile`, `metadata.json`, and
smoke assets. It should also check the child exit status, reject indeterminate
compile/deploy/test outcomes, and reserve success wording for a determinate
passing result. This guards against candidate-owned files and Make implicit
rules accidentally becoming the oracle.

The RealWorld Spring public check calls `/api/tags`, but its gold application
serves `/tags`; running the public check against the gold app returns HTTP 401.
The same check accepts the static fake because that fake happens to serve the
requested path. This makes both reference and negative controls mandatory.

Two additional authored-test probes show that corpus readiness varies by app:

- Petclinic Spring: 56 tests, 0 failures, 0 errors, 2 skipped.
- Coffee Shop Spring: 11 tests, 6 errors. Failures include missing
  `entityManagerFactory` test contexts and an invalid Mockito `doNothing` on a
  non-void method.

All nine gold persistence variants (`address-book`, `order`, and `roster`
crossed with Spring, Quarkus, and Jakarta) complete `mvn test` on JDK 21. This
is mostly a compile-only signal: eight produce no Surefire XML and therefore
run zero authored tests. Only roster Spring runs tests at that phase (2 tests,
0 failures, 0 errors). The evaluator-owned workflows above provide the missing
behavior and state coverage for the selected variants.
