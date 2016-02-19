#!/usr/bin/env perl

use strict;
use Getopt::Long ();
use PdfCollection::Meta;

my $mo = PdfCollection::Meta->new(verbose=>1);
my ($sha1, $autoslug, $args) = parse_args($mo, @ARGV);
die usage() unless $sha1 && ($args||$autoslug);

$mo->edit_meta($sha1, $args) if $args;
if ($autoslug) {
    my $slug = $mo->get_slug($sha1, save=>1, overwrite=>1);
    print "SLUG FOR $sha1: $slug\n";
}

#######

sub usage {
    return qq[
$0 sha1 [--autoslug] [key=value [key2="other value" ...]]

Update the meta.yml file for a given pdf from the command line.
Only scalar values are supported. '--autoslug' generates a new
slug and saves it to the meta.yml file (even if a slug was
already present).
];
}

sub parse_args {
    my $mo = shift;
    my $sha1 = shift;
    $sha1 = $mo->expand_sha1($sha1);
    my $autoslug = 0;
    my $gop = new Getopt::Long::Parser;
    $gop->getoptionsfromarray(\@_, "autoslug" => \$autoslug);
    my @kvpairs = @_;
    my %kv = ();
    foreach my $item (@kvpairs) {
        my ($k, $v) = split /=/, $item, 2;
        $v =~ s/^(["'])(.*)\1$/$1/s;
        $v =~ s/ +$//;
        $v =~ s/^ +//;
        $kv{$k} = $v;
    }
    return ($sha1, $autoslug) unless %kv;
    return ($sha1, $autoslug, \%kv);
}
