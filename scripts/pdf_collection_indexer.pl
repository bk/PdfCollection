#!/usr/bin/env perl

use strict;
use DBI;
use PdfCollection::SQLiteFTS;
use Getopt::Std qw(getopts);

our %opts = ();
getopts('hm', \%opts);
die usage() if $opts{h};


my $fts = PdfCollection::SQLiteFTS->new(verbose=>1);
$fts->index_all(meta_only=>$opts{m});

sub usage {
    return qq[
Usage: $0 [-h] [-m]

  -h: This help message
  -m: Update meta information only, not full text index
];
}
