use strict;
use warnings;
use ExtUtils::MakeMaker;

# Normalize version strings like 6.30_02 to 6.3002,
# so that we can do numerical comparisons on it.
my $eumm_version = $ExtUtils::MakeMaker::VERSION;
$eumm_version =~ s/_//;

WriteMakefile(
    NAME         => 'Food::Recipe',
    AUTHOR       => q{Gene Boggs <gene@ology.net>},
    VERSION_FROM => 'lib/Food/Recipe.pm',
    ABSTRACT     => 'Recipe Search Tool',
    ($eumm_version >= 6.3001 ? ('LICENSE'=> 'perl') : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More'       => 0,
        'Dancer'           => 1.3500,
        'Dancer::Cookies'  => 0,
        'File::Find::Rule' => 0,
        'List::Util'       => 0,
        'Math::Fraction'   => 0,
        'MealMaster'       => 0,
        'Storable'         => 0,
        'URI::Encode'      => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'Nutrients-DB-*' },
);
