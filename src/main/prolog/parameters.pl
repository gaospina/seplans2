% Amounts and rates of French inheritance law used by the rules.
% Every figure is in euros or percent and names its legal source.
% Figures as in force for deaths in 2026; check Legifrance before relying on them.

% allowance(+Category, -Euros)
% CGI art. 779 I: allowance in direct line (children and their representatives,
% father, mother and other ascendants).
allowance(direct_line, 100000).

% direct_line_scale(-Brackets)
% CGI art. 777, table I. Each bracket is UpperBoundEuros-RatePercent.
direct_line_scale([ 8072-5, 12109-10, 15932-15, 552324-20,
                    902838-30, 1805677-40, inf-45 ]).

% usufruct_scale(-Brackets)
% CGI art. 669 I: value of the usufruct as a percentage of full ownership,
% by age of the usufructuary. Each bracket is MaxAgeInYears-UsufructPercent
% ("less than 21 years old" is written as a maximum age of 20).
usufruct_scale([ 20-90, 30-80, 40-70, 50-60, 60-50,
                 70-40, 80-30, 90-20, inf-10 ]).
