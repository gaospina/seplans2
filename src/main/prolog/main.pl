% Entry point of the rule base.
%
%   swipl -q -g run -t halt main.pl
%
% reads the facts of one succession from standard input (one Prolog term per
% clause, see devolution.pl) and writes the result as one JSON object on
% standard output.

:- use_module(library(http/json)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(aggregate)).

:- include(parameters).
:- include(devolution).
:- include(tax).

run :-
    set_stream(user_output, encoding(utf8)),
    catch(( load_facts(user_input), solve(Result) ), Error, error_result(Error, Result)),
    json_write_dict(user_output, Result, [width(0)]),
    nl(user_output).

% --- loading facts -----------------------------------------------------------

load_facts(Stream) :-
    read_term(Stream, Term, []),
    (   Term == end_of_file
    ->  true
    ;   allowed_fact(Term)
    ->  assertz(Term),
        load_facts(Stream)
    ;   throw(invalid("Unexpected fact in the input."))
    ).

allowed_fact(estate_cents(N))   :- integer(N).
allowed_fact(person(Id, R))     :- atom(Id), atom(R), relation(R).
allowed_fact(predeceased(Id))   :- atom(Id).
allowed_fact(via(Id, Parent))   :- atom(Id), atom(Parent).
allowed_fact(line(Id, Line))    :- atom(Id), memberchk(Line, [paternal, maternal]).
allowed_fact(common_child(Id))  :- atom(Id).
allowed_fact(disabled(Id))      :- atom(Id).
allowed_fact(exempt_sibling(Id)) :- atom(Id).
allowed_fact(spouse_age(Age))   :- integer(Age).
allowed_fact(spouse_option(O))  :- memberchk(O, [usufruct, quarter]).

clear_facts :-
    retractall(estate_cents(_)),
    retractall(person(_, _)),
    retractall(predeceased(_)),
    retractall(via(_, _)),
    retractall(line(_, _)),
    retractall(common_child(_)),
    retractall(disabled(_)),
    retractall(exempt_sibling(_)),
    retractall(spouse_age(_)),
    retractall(spouse_option(_)).

% --- solving -----------------------------------------------------------------

% solve(-Result): Result is a dict ready to be written as JSON.
solve(_{status: ok, heirs: Heirs, note: Note, warnings: Warnings, usufructPercent: Percent}) :-
    validate,
    devolution(Shares),
    findall(Heir,
            ( person(Id, Relation), heir_result(Id, Relation, Shares, Heir) ),
            Heirs),
    (   Shares == []
    ->  Note = "Code civil art. 724 and 811: no heir among the listed relatives, the estate goes to the State."
    ;   Note = null
    ),
    findall(Warning, warning(Warning), Warnings),
    (   memberchk(share(_, usufruct, _, _), Shares)
    ->  usufruct_fraction(U),
        Percent is U * 100
    ;   Percent = null
    ).

% warning(-Text): something in the input that is accepted but worth a second look.
warning(Text) :-
    person(Id, Relation),
    memberchk(Relation, [child, descendant, sibling, sibling_descendant]),
    predeceased(Id),
    \+ effective(Id),
    format(string(Text), "~w died before the deceased and no living descendant of theirs is listed: they play no part in the split.", [Id]).
warning(Text) :-
    living(Id, descendant),
    living_link(Id),
    format(string(Text), "~w is listed although the parent who links them to the deceased is alive: they do not inherit.", [Id]).
warning(Text) :-
    living(Id, sibling_descendant),
    living_link(Id),
    format(string(Text), "~w is listed although the parent who links them to the deceased is alive: they do not inherit.", [Id]).

% People are named by their identifier in messages; the caller substitutes names.
validate :-
    (   estate_cents(E), E > 0
    ->  true
    ;   throw(invalid("The estate amount must be greater than zero."))
    ),
    (   person(_, _)
    ->  true
    ;   throw(invalid("List at least one relative."))
    ),
    forall(member(Relation, [spouse, pacs_partner, father, mother]), at_most_one_living(Relation)),
    (   living(_, spouse), living(_, pacs_partner)
    ->  throw(invalid("The deceased cannot have left both a spouse and a PACS partner."))
    ;   true
    ),
    forall(person(Id, descendant), valid_link(Id, [child, descendant])),
    forall(person(Id, sibling_descendant), valid_link(Id, [sibling, sibling_descendant])),
    forall(( person(Id, Relation), needs_line(Relation) ), has_line(Id)),
    forall(member(Line, [paternal, maternal]), at_most_two_grandparents(Line)),
    (   spouse_age(Age), ( Age < 0 ; Age > 130 )
    ->  throw(invalid("The spouse's age is not plausible."))
    ;   true
    ).

at_most_one_living(Relation) :-
    aggregate_all(count, living(_, Relation), Count),
    (   Count =< 1
    ->  true
    ;   invalid("There can be only one living ~w.", [Relation])
    ).

% valid_link(+Id, +ParentRelations): Id names a listed parent of the right kind,
% and the chain of parents does not loop.
valid_link(Id, ParentRelations) :-
    (   via(Id, Parent), Parent \== Id, person(Parent, Relation), memberchk(Relation, ParentRelations)
    ->  true
    ;   invalid("~w: choose the parent through whom this person is related to the deceased.", [Id])
    ),
    no_loop(Id, [Id]).

no_loop(Id, Seen) :-
    (   via(Id, Parent)
    ->  (   memberchk(Parent, Seen)
        ->  invalid("~w: the chain of parents loops back on itself.", [Id])
        ;   no_loop(Parent, [Parent|Seen])
        )
    ;   true
    ).

has_line(Id) :-
    (   line(Id, _)
    ->  true
    ;   invalid("~w: say whether this relative is on the father's or the mother's side.", [Id])
    ).

at_most_two_grandparents(Line) :-
    aggregate_all(count, ( living(G, grandparent), line(G, Line) ), Count),
    (   Count =< 2
    ->  true
    ;   invalid("There can be at most two living ~w grandparents.", [Line])
    ).

invalid(Format, Arguments) :-
    format(string(Message), Format, Arguments),
    throw(invalid(Message)).

heir_result(Id, Relation, Shares, Heir) :-
    memberchk(share(Id, Right, Fraction, Basis), Shares), !,
    share_value(Right, Fraction, Value),
    tax(Id, Relation, Value, Shares, tax(Status, Allowance, Taxable, Due, TaxBasis, Parts, Slices)),
    Net is Value - Due,
    maplist(part_dict, Parts, PartDicts),
    maplist(slice_dict, Slices, SliceDicts),
    fraction_text(Fraction, FractionText),
    cents(Value, ValueCents),
    cents(Allowance, AllowanceCents),
    cents(Taxable, TaxableCents),
    cents(Due, DueCents),
    cents(Net, NetCents),
    Heir = _{ id: Id, heir: true, right: Right, fraction: FractionText,
              valueCents: ValueCents, taxStatus: Status, allowanceCents: AllowanceCents,
              taxableCents: TaxableCents, taxCents: DueCents, netCents: NetCents,
              basis: Basis, taxBasis: TaxBasis,
              allowanceParts: PartDicts, brackets: SliceDicts }.
heir_result(Id, Relation, _, Heir) :-
    exclusion_basis(Id, Relation, Basis),
    Heir = _{ id: Id, heir: false, right: null, fraction: null,
              valueCents: null, taxStatus: null, allowanceCents: null, taxableCents: null,
              taxCents: null, netCents: null, basis: Basis, taxBasis: null,
              allowanceParts: [], brackets: [] }.

part_dict(part(Label, Amount), _{label: Label, cents: Cents}) :-
    cents(Amount, Cents).

slice_dict(slice(From, To, Rate, Amount),
           _{fromCents: FromCents, toCents: ToCents, rate: Rate, taxCents: Cents}) :-
    cents(From, FromCents),
    cents(To, ToCents),
    cents(Amount, Cents).

fraction_text(F, Text) :-
    rational(F, N, D),
    (   D =:= 1
    ->  format(string(Text), "~w", [N])
    ;   format(string(Text), "~w/~w", [N, D])
    ).

cents(null, null) :- !.
cents(Amount, Cents) :- Cents is round(Amount).

% --- errors ------------------------------------------------------------------

error_result(invalid(Message), _{status: invalid, message: Message}) :- !.
error_result(unsupported(Message), _{status: unsupported, message: Message}) :- !.
error_result(Error, _{status: error, message: Message}) :-
    format(string(Message), "~q", [Error]).
