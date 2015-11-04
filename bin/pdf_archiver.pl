#!/usr/bin/env perl

use strict;
use PdfCollection::Archiver;
use YAML qw/Dump/;

my $archiver = new PdfCollection::Archiver;

my $fn = shift
    or die qq{Archive a single PDF file, optionally with tags/meta-attr.
Usage: $0 pdf-file [meta-tag ...] ["attr:value" ...]
Current basedir: $archiver->{basedir}.
};

my @info = @ARGV;

binmode STDOUT, ":encoding(UTF-8)";

print Dump($archiver->archive($fn, @info));
