# Seplans2

Prototype web application that computes the split of a French estate between heirs and the
inheritance tax owed by each of them. The legal rules are written in Prolog (SWI-Prolog);
the web layer is Spring Boot.

See [PLAN.md](PLAN.md) for the architecture, legal scope and iteration plan.

This is a prototype for exploring rule-based legal reasoning. It is not legal or tax advice.

## What works today (iteration 1)

Living relatives of type spouse, child, father and mother:

| Family | Result |
|---|---|
| Children only | Equal shares |
| Spouse + children, all common | Spouse chooses: usufruct of everything, or 1/4 in full ownership |
| Spouse + at least one non-common child | Spouse 1/4, children share 3/4 |
| Spouse + both parents, no children | Spouse 1/2, each parent 1/4 |
| Spouse + one parent, no children | Spouse 3/4, parent 1/4 |
| Spouse alone | Everything |

The spouse is exempt from tax; children and parents are taxed on the direct-line scale after
the 100 000 € allowance. Under the usufruct option, shares are valued with the CGI art. 669
scale from the spouse's age. Any other family is answered with "not supported yet".

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

## Test

```
./mvnw test
```

runs the Prolog reference cases (`src/test/prolog`, plunit) and the end-to-end API tests,
which go through a real `swipl` process. The Prolog suite can also be run alone:

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
    { "name": "Luc", "relation": "CHILD", "commonChild": true }
  ]
}
```

The response has a `status` (`ok`, `unsupported`, `invalid`, `error`), a `message` when the
status is not `ok`, and one entry per person in `heirs` with the right, fraction, value,
allowance, taxable amount, tax, net amount and the legal basis.
