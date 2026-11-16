# Seplans2

Prototype web application that computes the split of a French estate between heirs and the
inheritance tax owed by each of them. The legal rules are written in Prolog (SWI-Prolog);
the web layer is Spring Boot.

See [PLAN.md](PLAN.md) for the architecture, legal scope and iteration plan.

This is a prototype for exploring rule-based legal reasoning. It is not legal or tax advice.

## What works today (iterations 1 to 5)

The page lists the relatives, checks the input, and shows for each person the share, the
tax and how every amount was reached: the rule and article applied, the allowances, and
the tax bracket by bracket. "Try an example" loads ready-made families.

Intestate devolution for the whole family, in the order set by the Code civil:

| Family | Result |
|---|---|
| Descendants, no spouse | Children share equally; descendants of a predeceased child take that child's share (representation, at any depth) |
| Spouse + descendants, all children common | Spouse chooses: usufruct of everything, or 1/4 in full ownership |
| Spouse + descendants, at least one non-common child | Spouse 1/4, descendants share 3/4 |
| Spouse, no descendants, both parents | Spouse 1/2, each parent 1/4 |
| Spouse, no descendants, one parent | Spouse 3/4, parent 1/4 |
| Spouse, no descendants, no parents | Spouse takes everything; siblings and other relatives are excluded |
| Parents and siblings | Each parent 1/4, siblings (or their descendants, by representation) share the rest |
| Siblings only | Siblings, or their descendants by representation, share everything |
| Parents only | 1/2 each; a sole parent shares half with the ascendants of the other line, or takes everything if there are none |
| Grandparents, great-grandparents | Half to each of the paternal and maternal lines, closest degree in each line; one line alone takes everything |
| Uncles, aunts, cousins… up to the 6th degree | Same split between lines, closest degree in each line |
| Nobody | The estate goes to the State |

PACS partners and cohabitants can be listed and are reported as not inheriting.

Inheritance tax for every heir:

| Heir | Allowance | Rate |
|---|---|---|
| Spouse | — | Exempt |
| Children, parents, grandparents | 100 000 € | Direct-line scale, 5 % to 45 % |
| Descendants representing a child | That child's 100 000 €, shared | Direct-line scale |
| Brother or sister | 15 932 € | 35 % up to 24 430 €, 45 % beyond; exempt under the conditions of CGI art. 796-0 ter |
| Nephews and nieces representing a sibling, several stems | That sibling's 15 932 €, shared | Sibling scale |
| Nephews and nieces of an only sibling | 7 967 € each | 55 % |
| Other relatives up to the 4th degree | 1 594 € | 55 % |
| Relatives of the 5th and 6th degree | 1 594 € | 60 % |
| Any disabled heir | + 159 325 € | — |

Under the usufruct option, shares are valued with the CGI art. 669 scale from the spouse's
age. Figures were checked against service-public.gouv.fr on 2026-11-16. Prior gifts, tax
reductions and the administration's rounding rules are not taken into account.

## Requirements

- JDK 25
- [SWI-Prolog](https://www.swi-prolog.org/) with `swipl` on the `PATH`
  (or set `seplans.swipl.command` in `application.properties`)

Maven is not needed: the Maven Wrapper downloads it on first use.

## Run

```
./mvnw spring-boot:run
```

then open http://localhost:8080. On Windows use `mvnw.cmd`.

Or with Docker, which needs neither Java nor SWI-Prolog on the machine:

```
docker build -t seplans2 .
docker run --rm -p 8080:8080 seplans2
```

`GET /api/health` says whether the rule engine can be run.

## Configuration

Set in `application.properties`, or as environment variables (`SEPLANS_SWIPL_TIMEOUT=5s`):

| Property | Default | Meaning |
|---|---|---|
| `seplans.swipl.command` | `swipl` | Command that starts SWI-Prolog |
| `seplans.swipl.timeout` | `10s` | Time allowed for one computation, including the wait for a free slot |
| `seplans.swipl.max-concurrent` | `4` | SWI-Prolog processes allowed to run at the same time |
| `seplans.swipl.stack-limit` | `256m` | Memory limit of the Prolog stacks of one process |

## Test

```
./mvnw test
```

runs the Prolog reference cases (`src/test/prolog`, plunit), the tests of the bridge, and
the end-to-end API tests, which go through a real `swipl` process. GitHub Actions runs the
same on every push, then builds the Docker image and computes one succession in it. The Prolog suite can also be run alone:

```
swipl -q -g run_tests -t halt src/test/prolog/succession_tests.pl
```

## How the bridge works

For each request the service writes the succession as Prolog facts, for example

```prolog
estate_cents(60000000).
person(p0, spouse).
person(p1, child).
common_child(p1).
person(p2, child).
predeceased(p2).
common_child(p2).
person(p3, descendant).
via(p3, p2).
spouse_option(usufruct).
spouse_age(65).
```

starts `swipl` on `src/main/prolog/main.pl`, sends the facts on standard input and reads one
JSON object from standard output. Names typed by the user never reach Prolog; people are
identified by generated ids.

## API

`POST /api/succession`

```json
{
  "estate": 600000,
  "spouseAge": 65,
  "spouseOption": "USUFRUCT",
  "persons": [
    { "name": "Claire", "relation": "SPOUSE" },
    { "name": "Luc", "relation": "CHILD", "commonChild": true },
    { "name": "Anne", "relation": "CHILD", "commonChild": true, "alive": false },
    { "name": "Zoe", "relation": "DESCENDANT", "via": 2 }
  ]
}
```

Per person: `relation` (see `Relation.java`), `alive` (default true), `via` (position in the
list, from 0, of the parent of a `DESCENDANT` or `SIBLING_DESCENDANT`), `line` (`PATERNAL`
or `MATERNAL`, for grandparents and other collaterals), `commonChild`, `disabled` and, for
a sibling, `siblingExemption`.

The response has a `status` (`ok`, `invalid`, `error`), a `message`, a list of `warnings`,
`usufructPercent` when the spouse takes the usufruct, and one entry per person in `heirs`
with the right, fraction, value, `taxStatus` (`exempt` or `computed`), `allowanceParts`,
`brackets`, allowance, taxable amount, tax, net amount and the legal basis.
