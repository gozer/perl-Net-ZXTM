#!/usr/bin/env perl
#
use strict;
use FindBin;

use Template;

my $tt = Template->new(
    {
        INCLUDE_PATH => "$FindBin::Bin/../tt",    # or list ref
        INTERPOLATE  => 1,                        # expand "$var" in plain text
        TRIM         => 1,                        # cleanup whitespace
        EVAL_PERL    => 1,                        # evaluate Perl code blocks
    }
);

use Storable;
my $tt_data = retrieve('index.storable');

$tt->process( 'index.tt', $tt_data, 'index.html' )
  || die $tt->error(), "\n";
