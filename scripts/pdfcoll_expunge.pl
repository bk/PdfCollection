#!/usr/bin/env perl

use strict;
use PdfCollection::SQLiteFTS;

my $id = shift || '';
die usage() unless $id eq 'auto' || $id =~ /^[a-f0-9]{40}$/;

my $fts = PdfCollection::SQLiteFTS->new;
my $dbh = $fts->{dbh};

my @sha1s = ();
if ($id eq 'auto') {
    my $meta_sha1s = $dbh->selectcol_arrayref("select folder_sha1 from meta");
    my $fts_sha1s = $dbh->selectcol_arrayref("select distinct folder_sha1 from page");
    my %cand = map {($_=>1)} @$meta_sha1s, @$fts_sha1s;
    my @cand = sort { $a cmp $b } keys %cand;
    my $basedir = $fts->{basedir};
    foreach my $sha1 (@cand) {
        my $dir = $basedir . '/' . substr($sha1, 0, 2) . '/' . $sha1;
        push @sha1s, $sha1 unless -d $dir;
    }
}
else {
    push @sha1s, $id;
}

foreach my $sha1 (@sha1s) {
    warn "EXPUNGING: $sha1\n";
    $fts->expunge($sha1);
}


sub usage {
    return qq[Usage: $0 sha1|'auto'

- If a sha1 is specified, that sha1 will be expunged from the
  index database.
- If 'auto' is specified, the script will look for sha1s in
  the index which are not found in the PDF root directory, and
  will expunge these.
];
}
