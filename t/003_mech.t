use strict;
use warnings;

BEGIN {
    use Test::More;
    use namespace::clean qw( pass );
}
use FindBin;
use Cwd qw( realpath );
use Dancer qw( :syntax );
use Dancer::Test;
use Test::WWW::Mechanize::PSGI;
set apphandler => 'PSGI';

my $appdir = realpath( "$FindBin::Bin/.." );
my $mech = Test::WWW::Mechanize::PSGI->new(
    app => sub {
        my $env = shift;
        setting(
            appname => 'Food::Recipe',
            appdir => $appdir,
        );
        load_app 'Food::Recipe';
        config->{environment} = 'test';
        Dancer::Config->load;
        my $request = Dancer::Request->new( env => $env );
        Dancer->dance( $request );
    }
);

$mech->get_ok('/') or diag $mech->content;

done_testing;
