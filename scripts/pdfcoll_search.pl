#!/usr/bin/env perl

use strict;
use PdfCollection::SQLiteFTS;
use PdfCollection::Meta;
use YAML qw/Dump/;
use JSON;

binmode STDIN, ":encoding(UTF-8)";
binmode STDOUT, ":encoding(UTF-8)";

my $format = 'normal';
my $query = shift or die usage();
if ($query eq '-json') {
    $format = 'json';
    $query = shift or die usage();
} elsif ($query eq '-yaml') {
    $format = 'yaml';
    $query = shift or die usage();
} elsif ($query =~ /^-/ && $query ne '-normal') {
    die "ERROR: Unrecognized format specified: '$query'\n";
}

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

if ($format eq 'json') {
    output_json(to_res(scalar(@$res), scalar(keys %found), %found));
} elsif ($format eq 'yaml') {
    output_yaml(to_res(scalar(@$res), scalar(keys %found), %found));
} else {
    output_normal(scalar(@$res), scalar(keys %found), %found);
}

sub output_normal {
    # Mixed plaintext and YAML datastructures. Sorted.
    my ($rescount, $keycount, %found) = @_;
    print "==> $rescount results found in $keycount works\n\n";
    my $cnt = 0;
    foreach my $row (sort {$b->{HITCOUNT} <=> $a->{HITCOUNT}} values %found) {
        $cnt++;
        print "============= item $cnt: ============\n";
        print Dump($row);
    }
}

sub output_json {
    my $res = shift;
    my $json = JSON->new->allow_nonref;
    print $json->pretty->encode($res);
}

sub output_yaml {
    my $res = shift;
    print Dump($res);
}

sub to_res {
    my ($rescount, $keycount, %found) = @_;
    return {
        result_count=>$rescount,
        document_count=>$keycount,
        results=>\%found,
    };
}

sub usage {
    return qq[Usage: $0 [-json|-yaml|-normal] 'query expression'

  Output formats:
    -json: Output as JSON
    -yaml: Output as YAML
    -normal: Output as semi-structured plaintext - the default

  Query expression:
    Use the syntax for sqlite FTS, with quote-grouping, uppercase
    boolean operators OR and AND, as well as NEAR. If you use a minus
    (meaning "not"), do not start the query with it.
];
}
