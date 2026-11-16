% Valuation of each heir's share and inheritance tax. All amounts are rational
% numbers of euro cents; rounding happens only when results are reported.

% share_value(+Right, +Fraction, -Cents)
share_value(full, F, Value) :-
    estate_cents(E),
    Value is F * E.
share_value(usufruct, F, Value) :-
    estate_cents(E),
    usufruct_fraction(U),
    Value is F * E * U.
share_value(bare, F, Value) :-
    estate_cents(E),
    usufruct_fraction(U),
    Value is F * E * (1 - U).

% usufruct_fraction(-U): value of the spouse's usufruct as a fraction of full
% ownership (CGI art. 669 I).
usufruct_fraction(U) :-
    (   spouse_age(Age)
    ->  true
    ;   throw(invalid("The spouse's age is needed to value the usufruct (CGI art. 669)."))
    ),
    usufruct_scale(Scale),
    member(MaxAge-Percent, Scale),
    ( MaxAge == inf ; Age =< MaxAge ), !,
    U is Percent rdiv 100.

% tax(+Id, +Relation, +Value, +Shares, -Tax)
% Tax is tax(Status, Allowance, Taxable, Due, Basis). Status is exempt, computed
% or pending (not computed yet); amounts that do not apply are null.
tax(_, spouse, _, _, tax(exempt, null, null, 0, Basis)) :- !,
    Basis = "CGI art. 796-0 bis: the surviving spouse is exempt from inheritance tax.".
tax(Id, Relation, Value, Shares, tax(computed, Allowance, Taxable, Due, Basis)) :-
    direct_line(Relation), !,
    allowance(direct_line, Euros),
    allowance_weight(Id, Relation, Shares, Weight),
    Allowance is min(Euros * 100 * Weight, Value),
    Taxable is Value - Allowance,
    direct_line_scale(Scale),
    scale_tax(Scale, 0, Taxable, 0, Due),
    (   Weight =:= 1
    ->  Basis = "CGI art. 779 I (allowance) and art. 777 (direct-line scale)."
    ;   Basis = "CGI art. 779 I: the allowance of the represented child is shared between the representatives; art. 777 (direct-line scale)."
    ).
tax(_, _, _, _, tax(pending, null, null, null, Basis)) :-
    Basis = "Inheritance tax between collaterals is not computed yet.".

direct_line(Relation) :-
    memberchk(Relation, [child, descendant, father, mother, grandparent, great_grandparent]).

% allowance_weight(+Id, +Relation, +Shares, -Weight)
% Representatives share the single allowance of the child they represent, in
% proportion to what each receives within that child's stem.
allowance_weight(Id, descendant, Shares, Weight) :- !,
    stem_root(Id, Root),
    findall(F, ( member(share(Other, _, F, _), Shares), stem_root(Other, Root) ), Fractions),
    sum_list(Fractions, StemTotal),
    memberchk(share(Id, _, Own, _), Shares),
    Weight is Own rdiv StemTotal.
allowance_weight(_, _, _, 1).

% stem_root(+Id, -Root): the child of the deceased from whom Id descends.
stem_root(Id, Root) :-
    (   via(Id, Parent)
    ->  stem_root(Parent, Root)
    ;   Root = Id
    ).

% scale_tax(+Brackets, +LowerCents, +TaxableCents, +Acc, -Due)
scale_tax([], _, _, Due, Due).
scale_tax([Upper-Rate|Brackets], Lower, Taxable, Acc0, Due) :-
    (   Taxable =< Lower
    ->  Due = Acc0
    ;   Upper == inf
    ->  Due is Acc0 + (Taxable - Lower) * Rate rdiv 100
    ;   UpperCents is Upper * 100,
        Top is min(Taxable, UpperCents),
        Acc is Acc0 + (Top - Lower) * Rate rdiv 100,
        scale_tax(Brackets, UpperCents, Taxable, Acc, Due)
    ).
