# Seplans2 — implementation plan

Prototype web application that computes how a French estate is split between heirs
and the inheritance tax each heir owes. The legal reasoning lives in Prolog; Spring Boot
provides the web layer and a bridge to the Prolog engine.

Status: iterations 1 and 2 are implemented (see README.md for what works). Iterations 3–5
are not started.

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
- `relation`: spouse, PACS partner, cohabitant, child, descendant (grandchild or further),
  father, mother, sibling, sibling's descendant (nephew, niece or further), grandparent,
  great-grandparent, uncle/aunt, great-uncle/great-aunt, first cousin, other collateral of
  the 5th or 6th degree
- `alive`: yes/no (predeceased children and siblings are listed so their descendants can
  represent them)
- `via`: for a descendant or a sibling's descendant, the listed parent who links this
  person to the deceased
- `line`: paternal or maternal, for ordinary ascendants and collaterals
- for a child: `commonChild` — whether the child is also the surviving spouse's child
- for the succession: `spouseAge`, and `spouseOption` (usufruct or quarter) when all
  children are common
- later iterations: `disabled`, `renounces`

The service turns this into Prolog facts (`estate_cents/1`, `person/2`, `predeceased/1`,
`via/2`, `line/2`, `common_child/1`, `spouse_age/1`, `spouse_option/1`), and the rules
derive everything else.

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
- Valuation of usufruct and bare ownership from the usufructuary's age (CGI art. 669),
  needed to tax the children when the spouse takes the usufruct

Out of scope for the prototype (candidates for later): wills and gifts, reserved portion
and reduction, recall of gifts made in the previous 15 years, liquidation of the matrimonial
regime, life insurance, the spouse's housing rights (art. 763–764), the siblings' right of
return on family property (art. 757-3), unworthiness, simple adoption, international
successions.

All amounts and rates go in `parameters.pl` with their source and date and must be
checked against the current texts on Légifrance before being relied on.

## 3. Iterations

Each iteration ends with a runnable application and passing tests.

**0 — Scaffold (done in this commit)**: repository, this plan.

**1 — Walking skeleton with spouse, children and parents**: Spring Boot project with Maven
Wrapper; the page (amount + rows of relatives); `POST /api/succession`; `PrologEngine` +
`SwiplProcessEngine`. Relations accepted: spouse, child, father, mother. Rules:

- Children only: equal shares (art. 735).
- Spouse with children who are all common: the spouse's option, chosen in the form —
  usufruct of the whole estate, or one quarter in full ownership (art. 757).
- Spouse with at least one non-common child: one quarter in full ownership (art. 757).
- Spouse without children, both parents alive: spouse 1/2, each parent 1/4; one parent
  alive: spouse 3/4, parent 1/4 (art. 757-1).
- Spouse without children or parents: the whole estate (art. 757-2).
- Tax: spouse exempt (CGI art. 796-0 bis); children and parents on the direct-line scale
  after their allowance. Under the usufruct option the children are taxed on the bare
  ownership, valued from the spouse's age with the CGI art. 669 scale.
- Any family outside these cases is answered with an explicit "not supported yet".

Tests: `plunit` for each rule above, one Spring integration test through the real bridge.

**2 — Devolution for all other relatives**: orders, degrees, representation, parents with
siblings, paternal/maternal split, estate with no heirs; the spouse excluding siblings and
other collaterals; PACS partners and cohabitants listed but excluded. A table of reference
cases (family → expected fractions) becomes the Prolog test suite. Tax is computed for every
direct-line heir (representatives share the allowance of the child they represent); for
brothers, sisters and other collaterals it is reported as "not computed yet" until iteration 3.

**3 — Complete tax computation**: every category, allowances, exemptions, disability,
representation. Reference cases checked against the official simulator on impots.gouv.fr.

**4 — Explanations and usability**: reasons shown per heir with the article cited; input
validation and clear errors (inconsistent family, missing `via`); cleaner UI.

**5 — Hardening**: timeouts and error handling on the Prolog process, GitHub Actions
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
2. When all children are common, the spouse's option is chosen by the user in the form
   (assumed). Alternative: show both variants side by side.
3. Is the estate amount the net estate already attributable to the deceased (after the
   matrimonial regime is settled and debts deducted)? The plan assumes yes.
