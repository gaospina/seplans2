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

test(two_spouses_rejected) :-
    with_facts([ estate_cents(40000000), person(s, spouse), person(t, spouse) ], R),
    R.status == invalid.

test(zero_estate_rejected) :-
    with_facts([ estate_cents(0), person(a, child) ], R),
    R.status == invalid.

:- end_tests(devolution).

% shares(+Result, -Pairs): Id-Fraction for every heir, in input order.
shares(Result, Pairs) :-
    findall(Id-F, ( member(H, Result.heirs), H.heir == true, Id = H.id, F = H.fraction ), Pairs).

:- begin_tests(representation).

test(grandchildren_represent_predeceased_child) :-
    with_facts([ estate_cents(40000000),
                 person(a, child),
                 person(b, child), predeceased(b),
                 person(g1, descendant), via(g1, b),
                 person(g2, descendant), via(g2, b) ], R),
    shares(R, [a-"1/2", g1-"1/4", g2-"1/4"]),
    heir(R, b, B), B.heir == false.

test(predeceased_child_without_descendants_is_ignored) :-
    with_facts([ estate_cents(40000000), person(a, child),
                 person(b, child), predeceased(b) ], R),
    shares(R, [a-"1"]).

test(grandchild_with_living_parent_is_excluded) :-
    with_facts([ estate_cents(40000000), person(a, child),
                 person(g, descendant), via(g, a) ], R),
    shares(R, [a-"1"]),
    heir(R, g, G), G.heir == false.

test(representation_goes_down_several_generations) :-
    % b and its child c are dead; c's two children take b's half.
    with_facts([ estate_cents(40000000), person(a, child),
                 person(b, child), predeceased(b),
                 person(c, descendant), via(c, b), predeceased(c),
                 person(d1, descendant), via(d1, c),
                 person(d2, descendant), via(d2, c) ], R),
    shares(R, [a-"1/2", d1-"1/4", d2-"1/4"]).

test(great_grandchild_blocked_by_living_grandchild) :-
    with_facts([ estate_cents(40000000),
                 person(b, child), predeceased(b),
                 person(c, descendant), via(c, b),
                 person(d, descendant), via(d, c) ], R),
    shares(R, [c-"1"]).

test(all_children_predeceased_split_by_stem) :-
    with_facts([ estate_cents(40000000),
                 person(a, child), predeceased(a),
                 person(b, child), predeceased(b),
                 person(a1, descendant), via(a1, a),
                 person(b1, descendant), via(b1, b),
                 person(b2, descendant), via(b2, b) ], R),
    shares(R, [a1-"1/2", b1-"1/4", b2-"1/4"]).

test(spouse_quarter_with_represented_stem) :-
    with_facts([ estate_cents(40000000), person(s, spouse),
                 person(a, child),
                 person(b, child), predeceased(b),
                 person(g1, descendant), via(g1, b),
                 person(g2, descendant), via(g2, b) ], R),
    shares(R, [s-"1/4", a-"3/8", g1-"3/16", g2-"3/16"]).

test(option_applies_when_represented_stems_are_common) :-
    with_facts([ estate_cents(40000000), person(s, spouse), spouse_age(75),
                 spouse_option(usufruct),
                 person(b, child), predeceased(b), common_child(b),
                 person(g, descendant), via(g, b) ], R),
    heir(R, s, S), S.right == usufruct,
    heir(R, g, G), G.right == bare, G.fraction == "1".

test(descendant_needs_a_parent) :-
    with_facts([ estate_cents(40000000), person(a, child), person(g, descendant) ], R),
    R.status == invalid.

test(descendant_parent_must_be_a_descendant) :-
    with_facts([ estate_cents(40000000), person(a, child), person(f, father),
                 person(g, descendant), via(g, f) ], R),
    R.status == invalid.

test(looping_chain_rejected) :-
    with_facts([ estate_cents(40000000), person(a, child),
                 person(g, descendant), via(g, h),
                 person(h, descendant), via(h, g) ], R),
    R.status == invalid.

:- end_tests(representation).

:- begin_tests(parents_and_siblings).

test(father_alone_takes_everything) :-
    with_facts([ estate_cents(40000000), person(f, father) ], R),
    shares(R, [f-"1"]).

test(both_parents_no_siblings) :-
    with_facts([ estate_cents(40000000), person(f, father), person(m, mother) ], R),
    shares(R, [f-"1/2", m-"1/2"]).

test(both_parents_with_siblings) :-
    with_facts([ estate_cents(40000000), person(f, father), person(m, mother),
                 person(s1, sibling), person(s2, sibling) ], R),
    shares(R, [f-"1/4", m-"1/4", s1-"1/4", s2-"1/4"]).

test(one_parent_with_siblings) :-
    with_facts([ estate_cents(40000000), person(m, mother),
                 person(s1, sibling), person(s2, sibling), person(s3, sibling) ], R),
    shares(R, [m-"1/4", s1-"1/4", s2-"1/4", s3-"1/4"]).

test(siblings_only) :-
    with_facts([ estate_cents(40000000), person(s1, sibling), person(s2, sibling) ], R),
    shares(R, [s1-"1/2", s2-"1/2"]).

test(nephews_represent_predeceased_sibling) :-
    with_facts([ estate_cents(40000000), person(s1, sibling),
                 person(s2, sibling), predeceased(s2),
                 person(n1, sibling_descendant), via(n1, s2),
                 person(n2, sibling_descendant), via(n2, s2) ], R),
    shares(R, [s1-"1/2", n1-"1/4", n2-"1/4"]).

test(nephews_alone_split_by_stem) :-
    with_facts([ estate_cents(40000000),
                 person(s1, sibling), predeceased(s1),
                 person(s2, sibling), predeceased(s2),
                 person(n1, sibling_descendant), via(n1, s1),
                 person(n2, sibling_descendant), via(n2, s2),
                 person(n3, sibling_descendant), via(n3, s2) ], R),
    shares(R, [n1-"1/2", n2-"1/4", n3-"1/4"]).

test(nephews_with_parent_take_three_quarters) :-
    with_facts([ estate_cents(40000000), person(f, father),
                 person(s, sibling), predeceased(s),
                 person(n, sibling_descendant), via(n, s) ], R),
    shares(R, [f-"1/4", n-"3/4"]).

test(parent_shares_with_ascendants_of_other_line) :-
    % Code civil art. 738-1
    with_facts([ estate_cents(40000000), person(f, father),
                 person(g1, grandparent), line(g1, maternal),
                 person(g2, grandparent), line(g2, maternal) ], R),
    shares(R, [f-"1/2", g1-"1/4", g2-"1/4"]).

test(parent_excludes_ascendants_of_own_line) :-
    with_facts([ estate_cents(40000000), person(f, father),
                 person(g, grandparent), line(g, paternal) ], R),
    shares(R, [f-"1"]).

test(siblings_exclude_grandparents) :-
    with_facts([ estate_cents(40000000), person(s, sibling),
                 person(g, grandparent), line(g, maternal) ], R),
    shares(R, [s-"1"]).

test(children_exclude_siblings) :-
    with_facts([ estate_cents(40000000), person(a, child), person(s, sibling) ], R),
    shares(R, [a-"1"]).

:- end_tests(parents_and_siblings).

:- begin_tests(ascendants_and_collaterals).

test(grandparents_split_between_lines) :-
    with_facts([ estate_cents(40000000),
                 person(p1, grandparent), line(p1, paternal),
                 person(p2, grandparent), line(p2, paternal),
                 person(m1, grandparent), line(m1, maternal) ], R),
    shares(R, [p1-"1/4", p2-"1/4", m1-"1/2"]).

test(one_line_of_grandparents_takes_everything) :-
    with_facts([ estate_cents(40000000),
                 person(p1, grandparent), line(p1, paternal),
                 person(u, uncle_aunt), line(u, maternal) ], R),
    shares(R, [p1-"1"]).

test(closest_ascendant_in_each_line) :-
    with_facts([ estate_cents(40000000),
                 person(p1, grandparent), line(p1, paternal),
                 person(p2, great_grandparent), line(p2, paternal),
                 person(m1, great_grandparent), line(m1, maternal) ], R),
    shares(R, [p1-"1/2", m1-"1/2"]).

test(collaterals_split_between_lines) :-
    with_facts([ estate_cents(40000000),
                 person(u, uncle_aunt), line(u, paternal),
                 person(c1, first_cousin), line(c1, maternal),
                 person(c2, first_cousin), line(c2, maternal) ], R),
    shares(R, [u-"1/2", c1-"1/4", c2-"1/4"]).

test(closest_collateral_in_a_line) :-
    with_facts([ estate_cents(40000000),
                 person(u, uncle_aunt), line(u, paternal),
                 person(c, first_cousin), line(c, paternal) ], R),
    shares(R, [u-"1"]).

test(same_degree_collaterals_share) :-
    with_facts([ estate_cents(40000000),
                 person(g, great_uncle_aunt), line(g, maternal),
                 person(c, first_cousin), line(c, maternal),
                 person(d, collateral_5), line(d, maternal) ], R),
    shares(R, [g-"1/2", c-"1/2"]).

test(sixth_degree_collateral_inherits) :-
    with_facts([ estate_cents(40000000), person(c, collateral_6), line(c, paternal) ], R),
    shares(R, [c-"1"]).

test(line_is_required) :-
    with_facts([ estate_cents(40000000), person(u, uncle_aunt) ], R),
    R.status == invalid.

test(spouse_excludes_siblings_and_grandparents) :-
    with_facts([ estate_cents(40000000), person(s, spouse), person(b, sibling),
                 person(g, grandparent), line(g, paternal) ], R),
    shares(R, [s-"1"]).

test(pacs_partner_does_not_inherit) :-
    with_facts([ estate_cents(40000000), person(p, pacs_partner), person(b, sibling) ], R),
    shares(R, [b-"1"]),
    heir(R, p, P), P.heir == false.

test(no_heir_estate_goes_to_the_state) :-
    with_facts([ estate_cents(40000000), person(c, cohabitant) ], R),
    R.status == ok,
    shares(R, []),
    R.note \== null.

test(predeceased_spouse_does_not_count) :-
    with_facts([ estate_cents(40000000), person(s, spouse), predeceased(s),
                 person(b, sibling) ], R),
    shares(R, [b-"1"]).

:- end_tests(ascendants_and_collaterals).

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

test(representatives_share_one_allowance) :-
    % g1 and g2 each receive 150 000 and half of b's 100 000 allowance:
    % 100 000 taxable, 1 380.75 + 16 813.60 = 18 194.35
    with_facts([ estate_cents(60000000),
                 person(a, child),
                 person(b, child), predeceased(b),
                 person(g1, descendant), via(g1, b),
                 person(g2, descendant), via(g2, b) ], R),
    heir(R, a, A), A.allowanceCents =:= 10000000,
    heir(R, g1, G), G.allowanceCents =:= 5000000, G.taxableCents =:= 10000000,
    G.taxCents =:= 1819435.

test(sole_representative_keeps_full_allowance) :-
    with_facts([ estate_cents(60000000),
                 person(b, child), predeceased(b),
                 person(g, descendant), via(g, b) ], R),
    heir(R, g, G), G.allowanceCents =:= 10000000.

test(grandparent_taxed_in_direct_line) :-
    with_facts([ estate_cents(30000000), person(g, grandparent), line(g, paternal) ], R),
    heir(R, g, G), G.taxStatus == computed, G.taxCents =:= 3819435.

:- end_tests(tax).

:- begin_tests(collateral_tax).

test(sibling_scale) :-
    % 300 000 - 15 932 = 284 068 taxable:
    % 24 430 x 35 % = 8 550.50, 259 638 x 45 % = 116 837.10, total 125 387.60
    with_facts([ estate_cents(30000000), person(s, sibling) ], R),
    heir(R, s, S), S.taxStatus == computed,
    S.allowanceCents =:= 1593200, S.taxableCents =:= 28406800,
    S.taxCents =:= 12538760, S.netCents =:= 17461240.

test(sibling_below_first_bracket) :-
    % 30 000 - 15 932 = 14 068 x 35 % = 4 923.80
    with_facts([ estate_cents(3000000), person(s, sibling) ], R),
    heir(R, s, S), S.taxCents =:= 492380.

test(exempt_sibling) :-
    with_facts([ estate_cents(30000000), person(s, sibling), exempt_sibling(s),
                 person(t, sibling) ], R),
    heir(R, s, S), S.taxStatus == exempt, S.taxCents =:= 0, S.netCents =:= 15000000,
    heir(R, t, T), T.taxStatus == computed, T.taxCents > 0.

test(nephews_by_representation_taxed_as_siblings) :-
    % Two stems. n1 and n2 receive 100 000 each and share s2's allowance:
    % 100 000 - 7 966 = 92 034 taxable, 8 550.50 + 67 604 x 45 % = 38 972.30
    with_facts([ estate_cents(40000000), person(s1, sibling),
                 person(s2, sibling), predeceased(s2),
                 person(n1, sibling_descendant), via(n1, s2),
                 person(n2, sibling_descendant), via(n2, s2) ], R),
    heir(R, n1, N), N.allowanceCents =:= 796600, N.taxableCents =:= 9203400,
    N.taxCents =:= 3897230.

test(nephew_of_single_stem_taxed_as_nephew) :-
    % 100 000 - 7 967 = 92 033 x 55 % = 50 618.15
    with_facts([ estate_cents(10000000),
                 person(s, sibling), predeceased(s),
                 person(n, sibling_descendant), via(n, s) ], R),
    heir(R, n, N), N.allowanceCents =:= 796700, N.taxCents =:= 5061815.

test(grand_nephew_of_single_stem) :-
    % Fourth degree: 100 000 - 1 594 = 98 406 x 55 % = 54 123.30
    with_facts([ estate_cents(10000000),
                 person(s, sibling), predeceased(s),
                 person(n, sibling_descendant), via(n, s), predeceased(n),
                 person(g, sibling_descendant), via(g, n) ], R),
    heir(R, g, G), G.allowanceCents =:= 159400, G.taxCents =:= 5412330.

test(uncle_taxed_at_55_percent) :-
    % 200 000 - 1 594 = 198 406 x 55 % = 109 123.30
    with_facts([ estate_cents(20000000), person(u, uncle_aunt), line(u, paternal) ], R),
    heir(R, u, U), U.taxCents =:= 10912330.

test(first_cousin_taxed_at_55_percent) :-
    with_facts([ estate_cents(20000000), person(c, first_cousin), line(c, maternal) ], R),
    heir(R, c, C), C.taxCents =:= 10912330.

test(fifth_degree_taxed_at_60_percent) :-
    % 198 406 x 60 % = 119 043.60
    with_facts([ estate_cents(20000000), person(c, collateral_5), line(c, maternal) ], R),
    heir(R, c, C), C.taxCents =:= 11904360.

:- end_tests(collateral_tax).

:- begin_tests(disability).

% The three cases below are the worked examples of service-public.gouv.fr (F35794).

test(official_example_disabled_child) :-
    % 300 000 - 259 325 = 40 675 taxable, duty 6 329.35
    with_facts([ estate_cents(30000000), person(a, child), disabled(a) ], R),
    heir(R, a, A), A.allowanceCents =:= 25932500, A.taxableCents =:= 4067500,
    A.taxCents =:= 632935.

test(official_example_child) :-
    % 150 000 - 100 000 = 50 000 taxable, duty 8 194.35
    with_facts([ estate_cents(15000000), person(a, child) ], R),
    heir(R, a, A), A.taxableCents =:= 5000000, A.taxCents =:= 819435.

test(official_example_disabled_sibling) :-
    % 200 000 - 175 257 = 24 743 taxable, duty 8 691.35
    with_facts([ estate_cents(20000000), person(s, sibling), disabled(s) ], R),
    heir(R, s, S), S.allowanceCents =:= 17525700, S.taxableCents =:= 2474300,
    S.taxCents =:= 869135.

test(disabled_representative_adds_allowance_to_shared_one) :-
    % g1 receives 150 000; allowance 50 000 (shared) + 159 325 caps at the share.
    with_facts([ estate_cents(60000000), person(a, child),
                 person(b, child), predeceased(b),
                 person(g1, descendant), via(g1, b), disabled(g1),
                 person(g2, descendant), via(g2, b) ], R),
    heir(R, g1, G1), G1.allowanceCents =:= 15000000, G1.taxCents =:= 0,
    heir(R, g2, G2), G2.allowanceCents =:= 5000000.

test(disabled_cousin) :-
    % 200 000 - (1 594 + 159 325) = 39 081 x 55 % = 21 494.55
    with_facts([ estate_cents(20000000), person(c, first_cousin), line(c, maternal),
                 disabled(c) ], R),
    heir(R, c, C), C.taxCents =:= 2149455.

:- end_tests(disability).
