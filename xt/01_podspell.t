use Test::More;
eval q{ use Test::Spelling };
plan skip_all => "Test::Spelling is not installed." if $@;
add_stopwords(map { split /[\s\:\-]/ } <DATA>);
$ENV{LANG} = 'C';
all_pod_files_spelling_ok('lib', 'bin');
__DATA__
motemen
motemen@gmail.com
App::htmlcat
stdin
PSGI
plackup
mala
