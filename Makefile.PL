use inc::Module::Install;

name 'App-htmlcat';
all_from 'lib/App/htmlcat.pm';

# requires '';

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';

auto_set_repository;
auto_include;

WriteAll;
