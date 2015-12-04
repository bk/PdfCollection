#!/usr/bin/env perl

use strict;
use YAML ();
use PdfCollection::Archiver;

binmode STDIN, ":encoding(UTF-8)";
binmode STDOUT, ":encoding(UTF-8)";

my $archiver = new PdfCollection::Archiver;

my $fn = shift
    or die qq{Usage: $0 pdf-file [meta-tag ...] [attr: value ...]
Basedir is: }.$archiver->{basedir}."\n";

my @info = @ARGV;

print YAML::Dump(
    $archiver->archive($fn, @info)
);
