use inc::Module::Install;

name 'App-htmlcat';
all_from 'lib/App/htmlcat.pm';

requires 'AnyEvent::Handle';
requires 'HTML::FromANSI::Tiny';
requires 'HTML::Entities';
requires 'Data::Section::Simple';
requires 'IO::Socket::INET';
requires 'Plack::Runner';
requires 'Twiggy';
requires 'Encode';

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';

install_script 'bin/htmlcat';

auto_set_repository;
auto_include;

WriteAll;
