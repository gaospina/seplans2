% Amounts and rates of French inheritance law used by the rules.
% Every figure is in euros or percent and names its legal source.
%
% Checked on 2026-11-16 against service-public.gouv.fr, pages F35794 (verified
% by the administration on 2026-08-19) and F934 (verified on 2026-07-03).

% allowance(+Category, -Euros)
allowance(direct_line,  100000).   % CGI art. 779 I: children and their representatives, ascendants
allowance(sibling,       15932).   % CGI art. 779 IV: brothers and sisters
allowance(nephew_niece,   7967).   % CGI art. 779 V: nephews and nieces
allowance(default,        1594).   % CGI art. 788 IV: when no other allowance applies
allowance(disability,   159325).   % CGI art. 779 II: disabled heir, added to the others

% scale(+Category, -Brackets)
% CGI art. 777. Each bracket is UpperBoundEuros-RatePercent.
scale(direct_line, [ 8072-5, 12109-10, 15932-15, 552324-20,
                     902838-30, 1805677-40, inf-45 ]).
scale(sibling,     [ 24430-35, inf-45 ]).
scale(fourth_degree, [ inf-55 ]).  % relatives up to the fourth degree inclusive
scale(remote,        [ inf-60 ]).  % relatives beyond the fourth degree

% usufruct_scale(-Brackets)
% CGI art. 669 I: value of the usufruct as a percentage of full ownership,
% by age of the usufructuary. Each bracket is MaxAgeInYears-UsufructPercent
% ("less than 21 years old" is written as a maximum age of 20).
usufruct_scale([ 20-90, 30-80, 40-70, 50-60, 60-50,
                 70-40, 80-30, 90-20, inf-10 ]).
