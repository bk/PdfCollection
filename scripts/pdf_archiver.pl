#!/usr/bin/env perl

use strict;
use YAML ();
use PdfCollection::Archiver;

binmode STDIN, ":encoding(UTF-8)";
binmode STDOUT, ":encoding(UTF-8)";

my $archiver = new PdfCollection::Archiver;

my $fn = shift
    or die qq{Archive a single PDF file, optionally with tags/meta-attr.
Usage: $0 pdf-file [meta-tag ...] ["attr: value" ...]
Current basedir: $archiver->{basedir}.
};

my @info = @ARGV;

print YAML::Dump(
    $archiver->archive($fn, @info)
);
