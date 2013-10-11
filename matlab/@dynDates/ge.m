function C = ge(A,B)

% Overloads the >= operator for dynDates objects.
%
% INPUTS 
%  o A    dynDates object with n or 1 elements.
%  o B    dynDates object with n or 1 elements.
%
% OUTPUTS 
%  o C    column vector of max(n,1) elements (zeros or ones).

% Copyright (C) 2013 Dynare Team
%
% This file is part of Dynare.
%
% Dynare is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% Dynare is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with Dynare.  If not, see <http://www.gnu.org/licenses/>.

if ~isequal(nargin,2)
    error('dynDates::ge: I need exactly two input arguments!')
end

if ~isa(A,'dynDates') || ~isa(B,'dynDates')
    error(['dynDates::ge: Input arguments ''' inputname(1) ''' and ''' inputname(2) ''' have to be a dynDates objects!'])
end

if ~isequal(A.freq,B.freq)
    C = 0;
    return
end

if isequal(A.ndat, B.ndat)
    C = (A==B);
    idx = find(C==0);
    for i=1:length(idx)
        C(idx(i)) = compare_vectors(@gt, A.time(idx(i),:), B.time(idx(i),:));
    end
else
    if isequal(A.ndat,1) && isequal(B.ndat,1)
        C = compare_vectors(@ge, A.time, B.time);
    elseif isequal(A.ndat,1)
        C = NaN(B.ndat,1);
        for i=1:B.ndat
            C(i) = compare_vectors(@ge, A.time, B.time(i,:));
        end
    elseif isequal(B.ndat,1)
        C = NaN(A.ndat,1);
        for i=1:A.ndat
            C(i) = compare_vectors(@ge, A.time(i,:), B.time);
        end
    else
        C = 0;
    end
end

%@test:1
%$ % Define some dates
%$ date_2 = '1950Q2';
%$ date_3 = '1950Q3';
%$ date_4 = '1950Q1';
%$ date_5 = '1949Q2';
%$
%$ % Call the tested routine.
%$ d2 = dynDates(date_2);
%$ d3 = dynDates(date_3);
%$ d4 = dynDates(date_4);
%$ d5 = dynDates(date_5);
%$ i1 = (d2>=d3);
%$ i2 = (d3>=d4);
%$ i3 = (d4>=d2);
%$ i4 = (d5>=d4);
%$ i5 = (d5>=d5); 
%$
%$ % Check the results.
%$ t(1) = dyn_assert(i1,0);
%$ t(2) = dyn_assert(i2,1);
%$ t(3) = dyn_assert(i3,0);
%$ t(4) = dyn_assert(i4,0);
%$ t(5) = dyn_assert(i5,1);
%$ T = all(t);
%@eof:1

%@test:2
%$ % Define some dates
%$ B1 = '1945Q1';
%$ B2 = '1945Q2';
%$ B3 = '1945Q3';
%$ B4 = '1945Q4';
%$ B5 = '1950Q1';
%$
%$ % Create dynDates objects.
%$ dd = dynDates(B1,B2,B3,B4);
%$
%$ % Check the results.
%$ t(1) = dyn_assert(dynDates(B1)>=dynDates(B2),0);
%$ t(2) = dyn_assert(dynDates(B2)>=dynDates(B1),1);
%$ t(3) = dyn_assert(dynDates(B2)>=dynDates(B2),1);
%$ t(4) = dyn_assert(dd>=dynDates(B5),zeros(4,1));
%$ t(5) = dyn_assert(dynDates(B5)>=dd,ones(4,1));
%$ t(6) = dyn_assert(dynDates(B1)>=dd,[1; zeros(3,1)]);
%$ T = all(t);
%@eof:2