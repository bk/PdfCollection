#!/usr/bin/env perl

use strict;
use DBI;
use PdfCollection::SQLiteFTS;

my $fts = PdfCollection::SQLiteFTS->new(verbose=>1);
$fts->index_all;
