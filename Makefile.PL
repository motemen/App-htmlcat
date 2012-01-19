use inc::Module::Install;

name 'App-htmlcat';
all_from 'lib/App/htmlcat.pm';

requires 'AnyEvent::Handle';
requires 'HTML::FromANSI::Tiny';
requires 'Data::Section::Simple';
requires 'List::MoreUtils';
requires 'Plack::Runner';

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';

install_script 'bin/htmlcat';

auto_set_repository;
auto_include;

WriteAll;
