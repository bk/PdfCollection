#!/usr/bin/env perl

use strict;
use PdfCollection::SQLiteFTS;
use PdfCollection::Meta;
use YAML qw/Dump/;
use JSON;

binmode STDIN, ":encoding(UTF-8)";
binmode STDOUT, ":encoding(UTF-8)";

my $format = 'normal';
my $fts_query = shift or die usage();
if ($fts_query eq '-json') {
    $format = 'json';
    $fts_query = shift or die usage();
} elsif ($fts_query eq '-yaml') {
    $format = 'yaml';
    $fts_query = shift or die usage();
} elsif ($fts_query eq '-normal') {
    $fts_query = shift or die usage();
} elsif ($fts_query =~ /^-/) {
    die "ERROR: Unrecognized format specified: '$fts_query'\n";
}
my @meta_queries = @ARGV;


my $fts = new PdfCollection::SQLiteFTS;
my $mo = new PdfCollection::Meta;

my %found = ();

my $res = $fts->search(
    $fts_query,
    search_meta=>1,
    meta_queries=>\@meta_queries);

foreach my $row (@$res) {
    # keys: offsets snippet file_name page_id folder_sha1
    my $sha1 = $row->{folder_sha1};
    unless ($found{$sha1}) {
        my $meta = $mo->read_meta($sha1);
        my @mk = keys %$meta;
        foreach my $k (@mk) {
            delete $meta->{$k} if $k =~ /^(pdfinfo|isbn_|now_ts)/;
        }
        $found{$sha1} = $meta;
        $found{$sha1}->{HITCOUNT} = 0;
        $found{$sha1}->{HITS} = [];
    }
    $found{$sha1}->{HITCOUNT}++;
    my $display;
    if ($row->{type} eq 'meta') {
        # we want entries with meta matches first
        $found{$sha1}->{HITCOUNT} += 10000;
        $display = {
            author  =>$row->{author},
            title   =>$row->{title},
            summary => $row->{summary},
            page    => 0,
        };
    }
    else {
        $display = {snippet=>$row->{snippet}};
        $display->{page} = int($1) if $row->{file_name} =~ /page_(\d+)/;
    }
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
    return qq[Usage: $0 [-json|-yaml|-normal] 'fts-query' [meta-queries]

  Output formats:

    -json: Output as JSON
    -yaml: Output as YAML
    -normal: Output as semi-structured plaintext - the default

  FTS-query expression:

    Use the syntax for sqlite FTS, with quote-grouping, uppercase
    boolean operators OR and AND, as well as NEAR. If you use a minus
    (meaning "not"), do not start the query with it.

  Meta-queries:

    These are string patterns for LIKE queries into meta data (they will be
    surrounded by '%'s automatically). They will be ORed together. If none is
    specified, the FTS query expression will be used as a meta query string
    also (which will not work very well unless you are only searching for a
    single term).

  Ordering:
    Results are ordered by number of hits. Each hit in the meta info counts
    as 10,000 ordinary hits, so these are always placed at the top of the
    reults.
]; }
