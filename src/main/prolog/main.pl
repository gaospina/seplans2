% Entry point of the rule base.
%
%   swipl -q -g run -t halt main.pl
%
% reads the facts of one succession from standard input (one Prolog term per
% clause, see devolution.pl) and writes the result as one JSON object on
% standard output.

:- use_module(library(http/json)).
:- use_module(library(lists)).

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
allowed_fact(person(Id, R))     :- atom(Id), memberchk(R, [spouse, child, father, mother]).
allowed_fact(common_child(Id))  :- atom(Id).
allowed_fact(spouse_age(Age))   :- integer(Age).
allowed_fact(spouse_option(O))  :- memberchk(O, [usufruct, quarter]).

clear_facts :-
    retractall(estate_cents(_)),
    retractall(person(_, _)),
    retractall(common_child(_)),
    retractall(spouse_age(_)),
    retractall(spouse_option(_)).

% --- solving -----------------------------------------------------------------

% solve(-Result): Result is a dict ready to be written as JSON.
solve(_{status: ok, heirs: Heirs}) :-
    validate,
    devolution(Shares),
    findall(Heir,
            ( person(Id, Relation), heir_result(Id, Relation, Shares, Heir) ),
            Heirs).

validate :-
    (   estate_cents(E), E > 0
    ->  true
    ;   throw(invalid("The estate amount must be greater than zero."))
    ),
    (   person(_, _)
    ->  true
    ;   throw(invalid("List at least one relative."))
    ),
    forall(member(Relation, [spouse, father, mother]), at_most_one(Relation)),
    (   spouse_age(Age), ( Age < 0 ; Age > 130 )
    ->  throw(invalid("The spouse's age is not plausible."))
    ;   true
    ).

at_most_one(Relation) :-
    aggregate_all(count, person(_, Relation), Count),
    (   Count =< 1
    ->  true
    ;   format(string(Message), "There can be only one ~w.", [Relation]),
        throw(invalid(Message))
    ).

heir_result(Id, _, Shares, Heir) :-
    memberchk(share(Id, Right, Fraction, Basis), Shares), !,
    person(Id, Relation),
    share_value(Right, Fraction, Value),
    tax(Relation, Value, tax(Allowance, Taxable, Due, TaxBasis)),
    Net is Value - Due,
    fraction_text(Fraction, FractionText),
    cents(Value, ValueCents),
    cents(Allowance, AllowanceCents),
    cents(Taxable, TaxableCents),
    cents(Due, DueCents),
    cents(Net, NetCents),
    Heir = _{ id: Id, heir: true, right: Right, fraction: FractionText,
              valueCents: ValueCents, allowanceCents: AllowanceCents,
              taxableCents: TaxableCents, taxCents: DueCents, netCents: NetCents,
              basis: Basis, taxBasis: TaxBasis }.
heir_result(Id, Relation, _, Heir) :-
    exclusion_basis(Relation, Basis),
    Heir = _{ id: Id, heir: false, right: null, fraction: null,
              valueCents: null, allowanceCents: null, taxableCents: null,
              taxCents: null, netCents: null, basis: Basis, taxBasis: null }.

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
    message_to_codes(Error, Codes),
    string_codes(Message, Codes).

message_to_codes(Error, Codes) :-
    format(codes(Codes), "~q", [Error]).
