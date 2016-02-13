#!/usr/bin/env perl

use strict;
use PdfCollection::Meta;
use PdfCollection::Archiver;
use YAML qw/Dump/;

my ($meta_file, $isbn, $force_update) = @ARGV;
die qq{Usage: $0 sha1_or_meta_file1 isbn [force_update]

Tries to retrieve meta info for a PDF based on ISBN,
and adds it to the meta.yml file if it is not already present.
} unless $meta_file && $isbn;

my $sha1 = $1 if $meta_file =~ /([a-f0-9]{40})/;
unless ($sha1) {
    die "Could not find sha1 in $meta_file\n";
}

my $m = new PdfCollection::Meta;
my $meta = $m->read_meta($sha1);
unless ($force_update) {
    die "Already have isbn_info for $sha1\n" if $meta->{isbn_info};
}
my $add = {
    isbn_info_source => 'Google Books',
    isbn_is_auto => 0,
    isbn => $isbn,
};
my $isbn_info = PdfCollection::Archiver::get_isbn_info($isbn);
if ($isbn_info && keys %$isbn_info) {
    $add->{isbn_info} = $isbn_info;
    $m->edit_meta($sha1, $add);
    print "===== $sha1 =======\n";
    print Dump($add);
} else {
    die "Could not retrieve anything for ISBN $isbn\n";
}
