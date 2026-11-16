% Devolution: who inherits, with which right and which fraction of the estate.
%
% Facts describing one succession (asserted before solving):
%   estate_cents(N)        net estate, in euro cents
%   person(Id, Relation)   a living relative; Relation is spouse, child, father or mother
%   common_child(Id)       the child is also the child of the surviving spouse
%   spouse_age(Years)      age of the surviving spouse
%   spouse_option(O)       usufruct or quarter (Code civil art. 757)

:- dynamic estate_cents/1, person/2, common_child/1, spouse_age/1, spouse_option/1.

children(Children) :- findall(C, person(C, child), Children).

parents(Parents) :-
    findall(P, ( person(P, R), memberchk(R, [father, mother]) ), Parents).

all_common(Children) :- forall(member(C, Children), common_child(C)).

% devolution(-Shares)
% Shares is a list of share(Id, Right, Fraction, Basis). Right is full, usufruct
% or bare (bare ownership). Fraction is a rational. Relatives without a share
% are not heirs.
devolution(Shares) :-
    children(Children), Children \== [], !,
    with_children(Children, Shares).
devolution(Shares) :-
    person(Spouse, spouse), !,
    parents(Parents),
    spouse_without_children(Spouse, Parents, Shares).
devolution(_) :-
    throw(unsupported("Without children or a spouse the estate goes to parents, siblings and other relatives. These cases are not supported yet.")).

with_children(Children, Shares) :-
    \+ person(_, spouse), !,
    length(Children, N),
    F is 1 rdiv N,
    child_shares(Children, full, F,
                 "Code civil art. 734 and 735: the children inherit in equal shares.",
                 Shares).
with_children(Children, [share(Spouse, usufruct, 1, SpouseBasis)|ChildShares]) :-
    person(Spouse, spouse),
    all_common(Children),
    chosen_option(usufruct), !,
    SpouseBasis = "Code civil art. 757: all children are common, the spouse chose the usufruct of the whole estate.",
    length(Children, N),
    F is 1 rdiv N,
    child_shares(Children, bare, F,
                 "Code civil art. 757: the children share the bare ownership equally.",
                 ChildShares).
with_children(Children, [share(Spouse, full, Quarter, SpouseBasis)|ChildShares]) :-
    person(Spouse, spouse),
    Quarter is 1 rdiv 4,
    (   all_common(Children)
    ->  SpouseBasis = "Code civil art. 757: all children are common, the spouse chose one quarter in full ownership."
    ;   SpouseBasis = "Code civil art. 757: at least one child is not the spouse's, the spouse receives one quarter in full ownership."
    ),
    length(Children, N),
    F is 3 rdiv (4 * N),
    child_shares(Children, full, F,
                 "Code civil art. 757: the children share the remaining three quarters equally.",
                 ChildShares).

% The option only exists when all children are common; it must then be stated.
chosen_option(Option) :-
    (   spouse_option(Chosen)
    ->  Option = Chosen
    ;   throw(invalid("All children are common: choose the spouse's option (usufruct of the whole estate, or one quarter in full ownership)."))
    ).

child_shares([], _, _, _, []).
child_shares([C|Cs], Right, F, Basis, [share(C, Right, F, Basis)|Shares]) :-
    child_shares(Cs, Right, F, Basis, Shares).

spouse_without_children(Spouse, [], [share(Spouse, full, 1, Basis)]) :- !,
    Basis = "Code civil art. 757-2: no descendants and no father or mother, the spouse receives the whole estate.".
spouse_without_children(Spouse, [Parent], Shares) :- !,
    SpouseF is 3 rdiv 4,
    ParentF is 1 rdiv 4,
    Shares = [ share(Spouse, full, SpouseF,
                     "Code civil art. 757-1: one parent survives, the spouse receives three quarters."),
               share(Parent, full, ParentF,
                     "Code civil art. 757-1: the surviving parent receives one quarter.") ].
spouse_without_children(Spouse, [P1, P2], Shares) :-
    Half is 1 rdiv 2,
    Quarter is 1 rdiv 4,
    ParentBasis = "Code civil art. 757-1: each parent receives one quarter.",
    Shares = [ share(Spouse, full, Half,
                     "Code civil art. 757-1: both parents survive, the spouse receives one half."),
               share(P1, full, Quarter, ParentBasis),
               share(P2, full, Quarter, ParentBasis) ].

% exclusion_basis(+Relation, -Basis): why a listed relative without a share is not an heir.
exclusion_basis(Relation, Basis) :-
    memberchk(Relation, [father, mother]), !,
    Basis = "Code civil art. 734: the descendants exclude the father and mother.".
exclusion_basis(_, "Not an heir in this succession.").
