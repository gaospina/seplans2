% Valuation of each heir's share and inheritance tax. All amounts are rational
% numbers of euro cents; rounding happens only when results are reported.
%
% Additional facts about a person:
%   disabled(Id)         entitled to the disability allowance (CGI art. 779 II)
%   exempt_sibling(Id)   a brother or sister meeting the conditions of CGI
%                        art. 796-0 ter (single, widowed, divorced or separated;
%                        over 50 or unable to work; lived with the deceased for
%                        the five years before the death)

:- dynamic disabled/1, exempt_sibling/1.

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
% Tax is tax(Status, Allowance, Taxable, Due, Basis, Parts, Slices). Status is
% exempt or computed; Allowance and Taxable are null for an exempt heir.
% Parts lists the allowances the heir is entitled to as part(Label, Cents);
% the allowance applied is their sum, capped at the value of the share.
% Slices lists the tax bracket by bracket as slice(FromCents, ToCents, RatePercent, Cents).
tax(_, spouse, _, _, tax(exempt, null, null, 0, Basis, [], [])) :- !,
    Basis = "CGI art. 796-0 bis: the surviving spouse is exempt from inheritance tax.".
tax(Id, sibling, _, _, tax(exempt, null, null, 0, Basis, [], [])) :-
    exempt_sibling(Id), !,
    Basis = "CGI art. 796-0 ter: a brother or sister who is single, over 50 or infirm, and lived with the deceased for five years is exempt.".
tax(Id, Relation, Value, Shares, tax(computed, Allowance, Taxable, Due, Basis, Parts, Slices)) :-
    regime(Id, Relation, Shares, AllowanceCategory, Weight, ScaleCategory, RegimeBasis),
    allowance(AllowanceCategory, Euros),
    Base is Euros * Weight * 100,
    allowance_label(AllowanceCategory, Weight, Label),
    (   disabled(Id)
    ->  allowance(disability, ExtraEuros),
        Extra is ExtraEuros * 100,
        Parts = [part(Label, Base), part("Disability allowance", Extra)],
        format(string(Basis), "~w CGI art. 779 II: the disability allowance is added.", [RegimeBasis])
    ;   Extra = 0,
        Parts = [part(Label, Base)],
        Basis = RegimeBasis
    ),
    Allowance is min(Base + Extra, Value),
    Taxable is Value - Allowance,
    scale(ScaleCategory, Scale),
    slices(Scale, 0, Taxable, Slices),
    sum_slices(Slices, 0, Due).

allowance_label(Category, Weight, Label) :-
    allowance_name(Category, Name),
    (   Weight =:= 1
    ->  Label = Name
    ;   rational(Weight, N, D),
        format(string(Label), "~w, ~w/~w of it by representation", [Name, N, D])
    ).

allowance_name(direct_line,  "Direct-line allowance").
allowance_name(sibling,      "Brother and sister allowance").
allowance_name(nephew_niece, "Nephew and niece allowance").
allowance_name(default,      "Default allowance").

% regime(+Id, +Relation, +Shares, -AllowanceCategory, -Weight, -ScaleCategory, -Basis)
% Weight is the part of the allowance the heir is entitled to: representatives
% share the single allowance of the person they represent.
regime(_, Relation, _, direct_line, 1, direct_line, Basis) :-
    memberchk(Relation, [child, father, mother, grandparent, great_grandparent]), !,
    Basis = "CGI art. 779 I (allowance) and art. 777 (direct-line scale).".
regime(Id, descendant, Shares, direct_line, Weight, direct_line, Basis) :- !,
    stem_weight(Id, Shares, Weight),
    (   Weight =:= 1
    ->  Basis = "CGI art. 779 I: a sole representative takes the allowance of the child represented; art. 777 (direct-line scale)."
    ;   Basis = "CGI art. 779 I: the allowance of the represented child is shared between the representatives; art. 777 (direct-line scale)."
    ).
regime(_, sibling, _, sibling, 1, sibling, Basis) :- !,
    Basis = "CGI art. 779 IV (allowance) and art. 777 (scale between brothers and sisters).".
regime(Id, sibling_descendant, Shares, sibling, Weight, sibling, Basis) :-
    several_sibling_stems, !,
    stem_weight(Id, Shares, Weight),
    Basis = "CGI art. 777 and 779 IV: coming by representation alongside other stems, they are taxed as the brother or sister represented, whose allowance they share.".
regime(Id, sibling_descendant, _, AllowanceCategory, 1, ScaleCategory, Basis) :- !,
    % A single stem: no representation for tax purposes, each is taxed on
    % their own relationship to the deceased.
    link_depth(Id, Depth),
    Degree is 2 + Depth,
    (   Depth =:= 1
    ->  AllowanceCategory = nephew_niece,
        Basis = "CGI art. 779 V (nephew and niece allowance) and art. 777 (55 % up to the fourth degree). With a single stem, representation has no effect on the tax."
    ;   AllowanceCategory = default,
        Basis = "CGI art. 788 IV (default allowance) and art. 777 (rate by degree of kinship). With a single stem, representation has no effect on the tax."
    ),
    degree_scale(Degree, ScaleCategory).
regime(_, Relation, _, default, 1, ScaleCategory, Basis) :-
    collateral_degree(Relation, Degree),
    degree_scale(Degree, ScaleCategory),
    (   ScaleCategory == fourth_degree
    ->  Basis = "CGI art. 788 IV (default allowance) and art. 777 (55 % between relatives up to the fourth degree)."
    ;   Basis = "CGI art. 788 IV (default allowance) and art. 777 (60 % beyond the fourth degree)."
    ).

degree_scale(Degree, fourth_degree) :- Degree =< 4, !.
degree_scale(_, remote).

several_sibling_stems :-
    roots(sibling, [_, _|_]).

% link_depth(+Id, -Depth): number of generations between Id and the child or
% sibling of the deceased from whom Id descends.
link_depth(Id, Depth) :-
    (   via(Id, Parent)
    ->  link_depth(Parent, Above),
        Depth is Above + 1
    ;   Depth = 0
    ).

% stem_weight(+Id, +Shares, -Weight): what Id receives as a part of everything
% received within the same stem.
stem_weight(Id, Shares, Weight) :-
    stem_root(Id, Root),
    findall(F, ( member(share(Other, _, F, _), Shares), stem_root(Other, Root) ), Fractions),
    sum_list(Fractions, StemTotal),
    memberchk(share(Id, _, Own, _), Shares),
    Weight is Own rdiv StemTotal.

% stem_root(+Id, -Root): the child or sibling of the deceased from whom Id descends.
stem_root(Id, Root) :-
    (   via(Id, Parent)
    ->  stem_root(Parent, Root)
    ;   Root = Id
    ).

% slices(+Brackets, +LowerCents, +TaxableCents, -Slices)
% One slice(FromCents, ToCents, RatePercent, TaxCents) per bracket reached.
slices([], _, _, []).
slices([Upper-Rate|Brackets], Lower, Taxable, Slices) :-
    (   Taxable =< Lower
    ->  Slices = []
    ;   (   Upper == inf
        ->  Top = Taxable
        ;   Top is min(Taxable, Upper * 100)
        ),
        Amount is (Top - Lower) * Rate rdiv 100,
        Slices = [slice(Lower, Top, Rate, Amount)|Rest],
        (   Upper == inf
        ->  Rest = []
        ;   UpperCents is Upper * 100,
            slices(Brackets, UpperCents, Taxable, Rest)
        )
    ).

sum_slices([], Due, Due).
sum_slices([slice(_, _, _, Amount)|Slices], Acc0, Due) :-
    Acc is Acc0 + Amount,
    sum_slices(Slices, Acc, Due).
