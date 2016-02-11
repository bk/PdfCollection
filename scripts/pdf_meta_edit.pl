#!/usr/bin/env perl

use strict;
use PdfCollection::Meta;

my $mo = PdfCollection::Meta->new(verbose=>1);
my ($sha1, $args) = parse_args($mo, @ARGV);
die usage() unless $sha1 && $args;

$mo->edit_meta($sha1, $args);

#######

sub usage {
    return qq[
$0 sha1 key=value [key2="other value" ...]

Update the meta.yml file for a given pdf from the command line.
Only scalar values are supported.
    ];
}

sub parse_args {
    my ($mo, $sha1, @kvpairs) = @_;
    my %kv = ();
    $sha1 = $mo->expand_sha1($sha1);
    foreach my $item (@kvpairs) {
        my ($k, $v) = split /=/, $item, 2;
        $v =~ s/^(["'])(.*)\1$/$1/s;
        $v =~ s/ +$//;
        $v =~ s/^ +//;
        $kv{$k} = $v;
    }
    return ($sha1) unless %kv;
    return ($sha1, \%kv);
}
