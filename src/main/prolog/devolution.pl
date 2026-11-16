% Devolution: who inherits, with which right and which fraction of the estate.
%
% Facts describing one succession (asserted before solving):
%   estate_cents(N)        net estate, in euro cents
%   person(Id, Relation)   a relative of the deceased, see relation/1
%   predeceased(Id)        the person died before the deceased
%   via(Id, ParentId)      the listed parent through whom a descendant, or a
%                          descendant of a sibling, is related to the deceased
%   line(Id, Line)         paternal or maternal, for ordinary ascendants and collaterals
%   common_child(Id)       the child is also the child of the surviving spouse
%   spouse_age(Years)      age of the surviving spouse
%   spouse_option(O)       usufruct or quarter (Code civil art. 757)

:- dynamic estate_cents/1, person/2, predeceased/1, via/2, line/2,
           common_child/1, spouse_age/1, spouse_option/1.

relation(spouse).
relation(pacs_partner).
relation(cohabitant).
relation(child).
relation(descendant).            % grandchild or further, linked by via/2
relation(father).
relation(mother).
relation(sibling).
relation(sibling_descendant).    % nephew, niece or further, linked by via/2
relation(grandparent).
relation(great_grandparent).
relation(Relation) :- collateral_degree(Relation, _).

% ascendant_degree(?Relation, ?Degree): ordinary ascendants.
ascendant_degree(grandparent, 2).
ascendant_degree(great_grandparent, 3).

% collateral_degree(?Relation, ?Degree): ordinary collaterals, who inherit up
% to the sixth degree (Code civil art. 745).
collateral_degree(uncle_aunt, 3).
collateral_degree(great_uncle_aunt, 4).
collateral_degree(first_cousin, 4).
collateral_degree(collateral_5, 5).
collateral_degree(collateral_6, 6).

needs_line(Relation) :- ascendant_degree(Relation, _).
needs_line(Relation) :- collateral_degree(Relation, _).

living(Id, Relation) :- person(Id, Relation), \+ predeceased(Id).

% effective(+Id): the person is alive, or is represented by a living descendant.
effective(Id) :- \+ predeceased(Id), !.
effective(Id) :- via(Child, Id), effective(Child), !.

% roots(+Relation, -Roots): the heads of the stems that take part in the split.
roots(Relation, Roots) :- findall(R, ( person(R, Relation), effective(R) ), Roots).

parents(Parents) :-
    findall(P, ( living(P, R), memberchk(R, [father, mother]) ), Parents).

% devolution(-Shares)
% Shares is a list of share(Id, Right, Fraction, Basis). Right is full, usufruct
% or bare (bare ownership). Fraction is a rational. Relatives without a share
% are not heirs; an empty list means the estate has no heir.
devolution(Shares) :-                       % first order: descendants
    roots(child, Stems), Stems \== [], !,
    with_descendants(Stems, Shares).
devolution(Shares) :-                       % spouse without descendants
    living(Spouse, spouse), !,
    parents(Parents),
    spouse_without_descendants(Spouse, Parents, Shares).
devolution(Shares) :-                       % second order: parents, siblings
    parents(Parents),
    roots(sibling, Siblings),
    ( Parents \== [] ; Siblings \== [] ), !,
    privileged(Parents, Siblings, Shares).
devolution(Shares) :-                       % third order: other ascendants
    nearest_ascendants(paternal, Paternal),
    nearest_ascendants(maternal, Maternal),
    ( Paternal \== [] ; Maternal \== [] ), !,
    split_lines(Paternal, Maternal,
                "Code civil art. 747 and 748: the estate is split in halves between the paternal and maternal ascendants; in each line the closest inherit.",
                "Code civil art. 748: no ascendant in the other line, the ascendants of this line inherit the whole estate.",
                Shares).
devolution(Shares) :-                       % fourth order: other collaterals
    nearest_collaterals(paternal, Paternal),
    nearest_collaterals(maternal, Maternal),
    ( Paternal \== [] ; Maternal \== [] ), !,
    split_lines(Paternal, Maternal,
                "Code civil art. 749 and 750: the estate is split in halves between the paternal and maternal collaterals; in each line the closest inherit.",
                "Code civil art. 749: no collateral in the other line, the collaterals of this line inherit the whole estate.",
                Shares).
devolution([]).

% --- descendants -------------------------------------------------------------

with_descendants(Stems, Shares) :-
    \+ living(_, spouse), !,
    stem_shares(Stems, 1, full,
                "Code civil art. 734 and 735: the children inherit in equal shares.",
                Shares).
with_descendants(Stems, [share(Spouse, usufruct, 1, SpouseBasis)|Rest]) :-
    living(Spouse, spouse),
    all_common(Stems),
    chosen_option(usufruct), !,
    SpouseBasis = "Code civil art. 757: all children are common, the spouse chose the usufruct of the whole estate.",
    stem_shares(Stems, 1, bare,
                "Code civil art. 757: the children share the bare ownership equally.",
                Rest).
with_descendants(Stems, [share(Spouse, full, Quarter, SpouseBasis)|Rest]) :-
    living(Spouse, spouse),
    Quarter is 1 rdiv 4,
    (   all_common(Stems)
    ->  SpouseBasis = "Code civil art. 757: all children are common, the spouse chose one quarter in full ownership."
    ;   SpouseBasis = "Code civil art. 757: at least one child is not the spouse's, the spouse receives one quarter in full ownership."
    ),
    Remainder is 3 rdiv 4,
    stem_shares(Stems, Remainder, full,
                "Code civil art. 757: the children share the remaining three quarters equally.",
                Rest).

all_common(Stems) :- forall(member(C, Stems), common_child(C)).

% The option only exists when all children are common; it must then be stated.
chosen_option(Option) :-
    (   spouse_option(Chosen)
    ->  Option = Chosen
    ;   throw(invalid("All children are common: choose the spouse's option (usufruct of the whole estate, or one quarter in full ownership)."))
    ).

% --- representation ----------------------------------------------------------

% stem_shares(+Roots, +Total, +Right, +Basis, -Shares)
% Total is split equally between the stems. A living root takes its stem's
% share; the share of a predeceased root goes down to its own stems
% (Code civil art. 751 to 754).
stem_shares(Roots, Total, Right, Basis, Shares) :-
    length(Roots, N),
    F is Total * (1 rdiv N),
    maplist(root_shares(F, Right, Basis), Roots, Nested),
    append(Nested, Shares).

root_shares(F, Right, Basis, Root, Shares) :-
    (   predeceased(Root)
    ->  findall(C, ( via(C, Root), effective(C) ), Representatives),
        stem_shares(Representatives, F, Right,
                    "Code civil art. 751 to 754: inherits by representation, taking the place of a predeceased parent.",
                    Shares)
    ;   Shares = [share(Root, Right, F, Basis)]
    ).

% --- spouse without descendants ----------------------------------------------

spouse_without_descendants(Spouse, [], [share(Spouse, full, 1, Basis)]) :- !,
    Basis = "Code civil art. 757-2: no descendants and no father or mother, the spouse receives the whole estate.".
spouse_without_descendants(Spouse, [Parent], Shares) :- !,
    SpouseF is 3 rdiv 4,
    ParentF is 1 rdiv 4,
    Shares = [ share(Spouse, full, SpouseF,
                     "Code civil art. 757-1: one parent survives, the spouse receives three quarters."),
               share(Parent, full, ParentF,
                     "Code civil art. 757-1: the surviving parent receives one quarter.") ].
spouse_without_descendants(Spouse, [P1, P2], Shares) :-
    Half is 1 rdiv 2,
    Quarter is 1 rdiv 4,
    ParentBasis = "Code civil art. 757-1: each parent receives one quarter.",
    Shares = [ share(Spouse, full, Half,
                     "Code civil art. 757-1: both parents survive, the spouse receives one half."),
               share(P1, full, Quarter, ParentBasis),
               share(P2, full, Quarter, ParentBasis) ].

% --- parents and siblings ----------------------------------------------------

% privileged(+Parents, +SiblingStems, -Shares)
privileged([], Siblings, Shares) :- !,
    stem_shares(Siblings, 1, full,
                "Code civil art. 737: no father or mother, the brothers and sisters inherit the whole estate.",
                Shares).
privileged([P1, P2], [], Shares) :- !,
    Half is 1 rdiv 2,
    equal_shares([P1, P2], Half,
                 "Code civil art. 736: no descendants, brothers or sisters, the father and mother each inherit one half.",
                 Shares).
privileged([Parent], [], Shares) :- !,
    person(Parent, Relation),
    other_line(Relation, Line),
    nearest_ascendants(Line, Ascendants),
    (   Ascendants == []
    ->  Shares = [share(Parent, full, 1,
                        "Code civil art. 736 and 738-1: no brothers or sisters and no ascendant in the other line, the surviving parent inherits the whole estate.")]
    ;   Half is 1 rdiv 2,
        length(Ascendants, N),
        Each is Half * (1 rdiv N),
        equal_shares(Ascendants, Each,
                     "Code civil art. 738-1: the ascendants of the predeceased parent's line inherit one half.",
                     AscendantShares),
        Shares = [share(Parent, full, Half,
                        "Code civil art. 738-1: the surviving parent inherits one half, the other half goes to the ascendants of the other line.")
                 |AscendantShares]
    ).
privileged(Parents, Siblings, Shares) :-
    Quarter is 1 rdiv 4,
    equal_shares(Parents, Quarter,
                 "Code civil art. 738: alongside brothers and sisters, each surviving parent inherits one quarter.",
                 ParentShares),
    length(Parents, N),
    Remainder is 1 - N * Quarter,
    stem_shares(Siblings, Remainder, full,
                "Code civil art. 738: the brothers and sisters share what the father and mother do not take.",
                SiblingShares),
    append(ParentShares, SiblingShares, Shares).

% other_line(+ParentRelation, -Line): the line of the parent who did not survive.
other_line(father, maternal).
other_line(mother, paternal).

% equal_shares(+Ids, +Each, +Basis, -Shares): every Id receives Each in full ownership.
equal_shares([], _, _, []).
equal_shares([Id|Ids], Each, Basis, [share(Id, full, Each, Basis)|Shares]) :-
    equal_shares(Ids, Each, Basis, Shares).

% --- ordinary ascendants and collaterals -------------------------------------

% nearest_ascendants(+Line, -Ascendants): the living ascendants of the closest
% degree in that line, [] if there are none.
nearest_ascendants(Line, Ascendants) :-
    member(Degree, [2, 3]),
    findall(A, ( ascendant_degree(Relation, Degree), living(A, Relation), line(A, Line) ),
            Ascendants),
    Ascendants \== [], !.
nearest_ascendants(_, []).

nearest_collaterals(Line, Collaterals) :-
    between(3, 6, Degree),
    findall(C, ( collateral_degree(Relation, Degree), living(C, Relation), line(C, Line) ),
            Collaterals),
    Collaterals \== [], !.
nearest_collaterals(_, []).

% split_lines(+Paternal, +Maternal, +BasisBothLines, +BasisOneLine, -Shares)
split_lines(Paternal, [], _, Basis, Shares) :- !,
    line_shares(Paternal, 1, Basis, Shares).
split_lines([], Maternal, _, Basis, Shares) :- !,
    line_shares(Maternal, 1, Basis, Shares).
split_lines(Paternal, Maternal, Basis, _, Shares) :-
    Half is 1 rdiv 2,
    line_shares(Paternal, Half, Basis, PaternalShares),
    line_shares(Maternal, Half, Basis, MaternalShares),
    append(PaternalShares, MaternalShares, Shares).

line_shares(Ids, Total, Basis, Shares) :-
    length(Ids, N),
    Each is Total * (1 rdiv N),
    equal_shares(Ids, Each, Basis, Shares).

% --- relatives who do not inherit --------------------------------------------

% exclusion_basis(+Id, +Relation, -Basis): why a listed relative has no share.
exclusion_basis(Id, _, Basis) :-
    predeceased(Id), !,
    Basis = "Died before the deceased.".
exclusion_basis(_, pacs_partner, Basis) :- !,
    Basis = "A PACS partner has no right in a succession without a will.".
exclusion_basis(_, cohabitant, Basis) :- !,
    Basis = "A cohabitant has no right in a succession without a will.".
exclusion_basis(Id, _, Basis) :-
    living_link(Id), !,
    Basis = "Code civil art. 752 and 754: the parent who links them to the deceased is alive, so they do not come by representation.".
exclusion_basis(_, _, Basis) :-
    roots(child, Stems), Stems \== [], !,
    Basis = "Code civil art. 734: the descendants exclude all other relatives.".
exclusion_basis(_, _, Basis) :-
    living(_, spouse), !,
    Basis = "Code civil art. 757-1 and 757-2: without descendants, the surviving spouse excludes all relatives other than the father and mother.".
exclusion_basis(_, _, "Code civil art. 734 and 744: excluded by heirs of a prior order or of a closer degree.").

% living_link(+Id): someone on the chain between Id and the deceased is alive.
living_link(Id) :-
    via(Id, Parent),
    (   \+ predeceased(Parent)
    ->  true
    ;   living_link(Parent)
    ).
