#!/usr/bin/env perl

use strict;
use PdfCollection::Meta;
use PdfCollection::Archiver;
use YAML qw/Dump/;

my ($meta_file, $doi, $force_update) = @ARGV;
die qq{Usage: $0 sha1_or_meta_file1 doi [force_update]

Tries to retrieve meta info for a PDF based on DOI,
and adds it to the meta.yml file if it is not already present.
} unless $meta_file && $doi;

my $sha1 = $1 if $meta_file =~ /([a-f0-9]{40})/;
unless ($sha1) {
    die "Could not find sha1 in $meta_file\n";
}

my $m = new PdfCollection::Meta;
my $meta = $m->read_meta($sha1);
unless ($force_update) {
    die "Already have DOI for $sha1\n" if $meta->{doi};
}
my $add = {
    doi => $doi,
    doi_is_auto => 0,
};
my ($bibrec, $bibkey) = PdfCollection::Archiver::get_bib($doi);
if ($bibrec && $bibkey) {
    my $data = PdfCollection::Archiver::parse_bibrec($bibrec);
    die "No valid data in bibrec" unless ref $data && %$data;
    $bibrec =~ s/^\s+//;
    $bibrec =~ s/\s+$//;
    $bibrec =~ s/\n/ /g;
    $add->{bibrec} = $bibrec;
    $add->{title} = $data->{title};
    $add->{author} = $data->{author};
    $add->{year} = $data->{year};
    $m->edit_meta($sha1, $add);
    print "===== $sha1 =======\n";
    print Dump($add);
} else {
    die "Could not retrieve anything for DOI $doi\n";
}
