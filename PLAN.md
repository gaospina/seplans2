# Seplans2 — implementation plan

Prototype web application that computes how a French estate is split between heirs
and the inheritance tax each heir owes. The legal reasoning lives in Prolog; Spring Boot
provides the web layer and a bridge to the Prolog engine.

Status: iteration 0 (repository scaffold). Nothing below is implemented yet.

## 1. Architecture

```
Browser (single page: estate amount + list of relatives)
   │  POST /api/succession  (JSON)
   ▼
Spring Boot
   ├─ SuccessionController      REST endpoint + serves the static page
   ├─ SuccessionService         validation, maps request → Prolog facts, result → DTO
   └─ PrologEngine (interface)  the bridge
        └─ SwiplProcessEngine   runs `swipl`, sends facts, reads JSON back
   ▼
Prolog (src/main/prolog)
   ├─ family.pl        derived relations: child, descendant, sibling, degree, line…
   ├─ devolution.pl    who inherits and which fraction (Code civil)
   ├─ tax.pl           allowances, brackets, exemptions (CGI)
   ├─ parameters.pl    every amount and rate as dated facts, with its legal source
   └─ main.pl          entry point: load facts → solve → print JSON
```

### Decisions and why

| Topic | Choice | Reason |
|---|---|---|
| Prolog system | SWI-Prolog (10.0.0 is installed locally) | Mature, built-in JSON, rationals for exact fractions, `plunit` for tests |
| Bridge | `swipl` launched as a subprocess per request, JSON on stdout, hidden behind a `PrologEngine` interface | No JNI or native-library path setup, no shared mutable Prolog state between requests, easy to test. JPL (in-process) can replace it later behind the same interface if latency matters |
| Build | Maven via the Maven Wrapper (`mvnw`) | Neither Maven nor Gradle is installed; the wrapper needs only the JDK |
| Java / Spring | Java 25 (installed), Spring Boot 4.x | Current LTS and current Boot line |
| Frontend | One static HTML page + plain JavaScript calling the REST API | "Simple frontend"; no Node toolchain. Can be swapped for a richer UI later without touching the backend |
| Arithmetic | Shares as rational numbers in Prolog, money rounded only at the end | Avoids 1/3 + 1/3 + 1/3 ≠ 1 errors |
| Persistence | None | Each computation is stateless |

### Input model

A flat "relationship to the deceased" label is not enough: representation (a grandchild
taking the place of a predeceased child) and the paternal/maternal split need to know
*through whom* someone is related. Each person is therefore encoded as:

- `id`, `name`
- `relation`: spouse, PACS partner, child, grandchild, father, mother, sibling,
  nephew/niece, grandparent, uncle/aunt, cousin, other
- `alive`: yes/no (predeceased relatives are listed so their descendants can represent them)
- `via`: the id of the relative who links this person to the deceased, when relevant
  (e.g. the grandchild's parent)
- later iterations: `line` (paternal/maternal), `disabled`, `renounces`

The service turns this into Prolog facts (`person/2`, `parent_of/2`, `predeceased/1`,
`spouse/1`, `estate/1`), and the rules derive everything else.

### Output model

For each listed person: heir or not, fraction, gross amount, allowance applied, taxable
amount, tax, net amount — plus a list of reasons (the rule and legal article that applied),
so that a result can be checked against the law rather than trusted blindly.

## 2. Legal scope

In scope (intestate succession, "dévolution légale"):

- The four orders of heirs and ranking by degree (Code civil art. 734 ff.)
- Representation among descendants and among siblings' descendants (art. 751 ff.)
- Parents alongside siblings (art. 738), split between paternal and maternal lines (art. 746 ff.)
- Surviving spouse (art. 756 ff.), including the choice between usufruct of everything and
  one quarter in full ownership when all children are common
- PACS partner and cohabitant: no intestate rights
- Inheritance tax: allowance per relationship, progressive scale in direct line, sibling,
  up-to-4th-degree and other rates, spouse/PACS exemption, conditional sibling exemption,
  disability allowance, allowance sharing under representation (CGI art. 777, 779, 796-0)

Out of scope for the prototype (candidates for later): wills and gifts, reserved portion
and reduction, recall of gifts made in the previous 15 years, liquidation of the matrimonial
regime, life insurance, valuation of usufruct (CGI art. 669), unworthiness, simple adoption,
international successions.

All amounts and rates go in `parameters.pl` with their source and date and must be
checked against the current texts on Légifrance before being relied on.

## 3. Iterations

Each iteration ends with a runnable application and passing tests.

**0 — Scaffold (done in this commit)**: repository, this plan.

**1 — Walking skeleton**: Spring Boot project with Maven Wrapper; the page (amount + rows
of relatives); `POST /api/succession`; `PrologEngine` + `SwiplProcessEngine`; Prolog handles
the simplest case only — living children share equally, taxed on the direct-line scale.
Tests: `plunit` for the rules, one Spring integration test through the real bridge.

**2 — Devolution without a spouse**: orders, degrees, representation, parents with siblings,
paternal/maternal split, estate with no heirs. A table of reference cases
(family → expected fractions) becomes the Prolog test suite.

**3 — Surviving spouse and partners**: spouse with common / non-common children, with
parents, alone; the usufruct option as an input; PACS and cohabitants excluded.

**4 — Complete tax computation**: every category, allowances, exemptions, disability,
representation. Reference cases checked against the official simulator on impots.gouv.fr.

**5 — Explanations and usability**: reasons shown per heir with the article cited; input
validation and clear errors (inconsistent family, missing `via`); cleaner UI.

**6 — Hardening**: timeouts and error handling on the Prolog process, GitHub Actions
(JDK + SWI-Prolog), packaging (Docker image containing both runtimes).

**Later**: wills and gifts, reserved portion, JPL engine, family-tree editor.

## 4. Repository layout (from iteration 1)

```
pom.xml, mvnw, mvnw.cmd
src/main/java/…/seplans/      controller, service, bridge, DTOs
src/main/prolog/              the rule base
src/main/resources/static/    index.html, app.js, style.css
src/test/java/                Spring tests
src/test/prolog/              plunit suites and reference cases
```

## 5. Open questions

1. Should the UI be in French, English, or both?
2. When all children are common, should the spouse's option be chosen by the user, or
   should the result show both variants side by side?
3. Is the estate amount the net estate already attributable to the deceased (after the
   matrimonial regime is settled and debts deducted)? The plan assumes yes.
