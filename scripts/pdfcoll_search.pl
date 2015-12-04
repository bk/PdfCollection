#!/usr/bin/env perl

use strict;
use PdfCollection::SQLiteFTS;
use PdfCollection::Meta;
use YAML qw/Dump/;

binmode STDIN, ":encoding(UTF-8)";
binmode STDOUT, ":encoding(UTF-8)";

my $query = shift or die "Usage: $0 'query expression'\n";

my $fts = new PdfCollection::SQLiteFTS;
my $mo = new PdfCollection::Meta;

my %found = ();

my $res = $fts->search($query);

foreach my $row (@$res) {
    # keys: offsets snippet file_name page_id folder_sha1
    my $sha1 = $row->{folder_sha1};
    unless ($found{$sha1}) {
        $found{$sha1} = $mo->read_meta($sha1);
        $found{$sha1}->{HITCOUNT} = 0;
        $found{$sha1}->{HITS} = [];
    }
    $found{$sha1}->{HITCOUNT}++;
    my $display = {snippet=>$row->{snippet}};
    $display->{page} = int($1) if $row->{file_name} =~ /page_(\d+)/;
    push @{$found{$sha1}->{HITS}}, $display;
}

print "==> ", scalar(@$res), " results found in ", scalar(keys %found), " works\n\n";

my $cnt = 0;

foreach my $row (sort {$b->{HITCOUNT} <=> $a->{HITCOUNT}} values %found) {
    $cnt++;
    print "============= item $cnt: ============\n";
    print Dump($row);
}
