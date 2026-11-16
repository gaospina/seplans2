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

% tax(+Relation, +Value, -Tax)
% Tax is tax(Allowance, Taxable, Due, Basis); Allowance and Taxable are null
% when the heir is exempt.
tax(spouse, _, tax(null, null, 0, Basis)) :- !,
    Basis = "CGI art. 796-0 bis: the surviving spouse is exempt from inheritance tax.".
tax(Relation, Value, tax(Allowance, Taxable, Due, Basis)) :-
    allowance(Relation, Euros),
    Allowance is min(Euros * 100, Value),
    Taxable is Value - Allowance,
    direct_line_scale(Scale),
    scale_tax(Scale, 0, Taxable, 0, Due),
    Basis = "CGI art. 779 I (allowance) and art. 777 (direct-line scale).".

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
