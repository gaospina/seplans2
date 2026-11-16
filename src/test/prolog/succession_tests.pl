% Reference cases for the rule base.
%
%   swipl -q -g run_tests -t halt src/test/prolog/succession_tests.pl

:- use_module(library(plunit)).
:- load_files('../../main/prolog/main', []).

% with_facts(+Facts, -Result): solve one succession described by Facts.
with_facts(Facts, Result) :-
    setup_call_cleanup(
        ( clear_facts, maplist(assertz, Facts) ),
        catch(solve(Result), Error, error_result(Error, Result)),
        clear_facts).

% heir(+Result, +Id, -Dict)
heir(Result, Id, Heir) :-
    member(Heir, Result.heirs),
    Heir.id == Id, !.

:- begin_tests(devolution).

test(children_only_equal_shares) :-
    with_facts([ estate_cents(60000000), person(a, child), person(b, child) ], R),
    R.status == ok,
    heir(R, a, A), A.fraction == "1/2", A.right == full, A.valueCents =:= 30000000,
    heir(R, b, B), B.fraction == "1/2".

test(single_child_takes_everything) :-
    with_facts([ estate_cents(10000000), person(a, child) ], R),
    heir(R, a, A), A.fraction == "1", A.valueCents =:= 10000000.

test(children_exclude_parents) :-
    with_facts([ estate_cents(10000000), person(a, child), person(m, mother) ], R),
    heir(R, m, M), M.heir == false,
    heir(R, a, A), A.fraction == "1".

test(spouse_quarter_with_common_children) :-
    with_facts([ estate_cents(60000000), person(s, spouse),
                 person(a, child), person(b, child),
                 common_child(a), common_child(b),
                 spouse_option(quarter) ], R),
    heir(R, s, S), S.fraction == "1/4", S.right == full, S.valueCents =:= 15000000,
    heir(R, a, A), A.fraction == "3/8", A.valueCents =:= 22500000.

test(spouse_usufruct_with_common_children) :-
    with_facts([ estate_cents(60000000), person(s, spouse),
                 person(a, child), person(b, child),
                 common_child(a), common_child(b),
                 spouse_option(usufruct), spouse_age(65) ], R),
    % CGI art. 669: at 65 the usufruct is worth 40 %.
    heir(R, s, S), S.right == usufruct, S.fraction == "1", S.valueCents =:= 24000000,
    heir(R, a, A), A.right == bare, A.fraction == "1/2", A.valueCents =:= 18000000.

test(option_required_when_all_children_common) :-
    with_facts([ estate_cents(60000000), person(s, spouse),
                 person(a, child), common_child(a) ], R),
    R.status == invalid.

test(usufruct_needs_spouse_age) :-
    with_facts([ estate_cents(60000000), person(s, spouse),
                 person(a, child), common_child(a), spouse_option(usufruct) ], R),
    R.status == invalid.

test(non_common_child_forces_quarter) :-
    % The option is ignored: one child is not the spouse's.
    with_facts([ estate_cents(40000000), person(s, spouse),
                 person(a, child), person(b, child), common_child(a),
                 spouse_option(usufruct), spouse_age(65) ], R),
    heir(R, s, S), S.right == full, S.fraction == "1/4",
    heir(R, b, B), B.right == full, B.fraction == "3/8".

test(spouse_with_both_parents) :-
    with_facts([ estate_cents(40000000), person(s, spouse),
                 person(f, father), person(m, mother) ], R),
    heir(R, s, S), S.fraction == "1/2",
    heir(R, f, F), F.fraction == "1/4", F.valueCents =:= 10000000,
    heir(R, m, M), M.fraction == "1/4".

test(spouse_with_one_parent) :-
    with_facts([ estate_cents(40000000), person(s, spouse), person(m, mother) ], R),
    heir(R, s, S), S.fraction == "3/4", S.valueCents =:= 30000000,
    heir(R, m, M), M.fraction == "1/4".

test(spouse_alone) :-
    with_facts([ estate_cents(40000000), person(s, spouse) ], R),
    heir(R, s, S), S.fraction == "1", S.valueCents =:= 40000000.

test(parents_only_not_supported_yet) :-
    with_facts([ estate_cents(40000000), person(f, father) ], R),
    R.status == unsupported.

test(two_spouses_rejected) :-
    with_facts([ estate_cents(40000000), person(s, spouse), person(t, spouse) ], R),
    R.status == invalid.

test(zero_estate_rejected) :-
    with_facts([ estate_cents(0), person(a, child) ], R),
    R.status == invalid.

:- end_tests(devolution).

:- begin_tests(tax).

test(spouse_is_exempt) :-
    with_facts([ estate_cents(40000000), person(s, spouse) ], R),
    heir(R, s, S), S.taxCents =:= 0, S.netCents =:= 40000000, S.allowanceCents == null.

test(child_below_allowance_pays_nothing) :-
    with_facts([ estate_cents(8000000), person(a, child) ], R),
    heir(R, a, A), A.allowanceCents =:= 8000000, A.taxableCents =:= 0, A.taxCents =:= 0.

test(child_direct_line_scale) :-
    % 300 000 each, 200 000 taxable:
    % 403.60 + 403.70 + 573.45 + 36 813.60 = 38 194.35
    with_facts([ estate_cents(60000000), person(a, child), person(b, child) ], R),
    heir(R, a, A),
    A.allowanceCents =:= 10000000, A.taxableCents =:= 20000000,
    A.taxCents =:= 3819435, A.netCents =:= 26180565.

test(child_taxed_on_bare_ownership) :-
    % Bare ownership 180 000, 80 000 taxable: 1 380.75 + 12 813.60 = 14 194.35
    with_facts([ estate_cents(60000000), person(s, spouse),
                 person(a, child), person(b, child),
                 common_child(a), common_child(b),
                 spouse_option(usufruct), spouse_age(65) ], R),
    heir(R, a, A), A.taxableCents =:= 8000000, A.taxCents =:= 1419435.

test(parent_taxed_in_direct_line) :-
    % Parent receives 1/4 of 1 000 000 = 250 000, 150 000 taxable:
    % 1 380.75 + 26 813.60 = 28 194.35
    with_facts([ estate_cents(100000000), person(s, spouse), person(m, mother) ], R),
    heir(R, m, M), M.taxCents =:= 2819435.

test(top_bracket) :-
    % 2 100 000 to one child, 2 000 000 taxable.
    % 1 380.75 + 107 278.40 + 105 154.20 + 361 135.60 + 87 445.35 = 662 394.30
    with_facts([ estate_cents(210000000), person(a, child) ], R),
    heir(R, a, A), A.taxCents =:= 66239430.

test(usufruct_scale_boundaries) :-
    forall(member(Age-Percent, [20-90, 21-80, 60-50, 61-40, 90-20, 91-10]),
           ( with_facts([ estate_cents(10000000), person(s, spouse),
                          person(a, child), common_child(a),
                          spouse_option(usufruct), spouse_age(Age) ], R),
             heir(R, s, S),
             S.valueCents =:= Percent * 100000 )).

:- end_tests(tax).
