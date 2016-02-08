#!/usr/bin/env perl

use strict;
use PdfCollection::Meta;
use Cwd qw/abs_path/;
use File::Copy qw/copy/;

my $sha1 = shift or die usage();
$sha1 = expand_sha1($sha1);
$sha1 = $1 if $sha1 =~ /([a-f0-9]{40})/;

my $m = new PdfCollection::Meta;
my $meta = $m->read_meta($sha1) or die "Could not find meta for $sha1\n";

my $path = $meta->{full_path};
my $realpath = abs_path($path);

die "Could not find real PDF file for $sha1\n" unless $realpath;

my $target = $m->get_slug($sha1) . '.pdf';

warn "=> ./$target will point to $realpath\n";
die "Target $target already exists\n" if -e "./$target";
link($realpath, "./$target")
    or copy($realpath, "./$target")
    or die "Could neither hardlink not copy $realpath to $target: $!\n";


sub usage {
    return qq[Usage: $0 sha1-sum

Places the PDF file corresponding to the (possibly partial) sha1 sum (or
contained in the pdf collection directory in question) in the current
working directory, with a filename based on the slug of the file. Attempts
to hardlink the file, but if that does not succeed, creates a symlink to it.
Prints an error message if the file is not present in the source directory
(e.g. if it has been evicted from this repository by git-annex) or if it
already exists in the current directory.
];
}

sub expand_sha1 {
    my $sha1 = shift;
    # Expand partial sha1 -- for a medium-size collection
    # a minimum of 5 characters is enough
    if (length($sha1) < 40 && length($sha1) > 4) {
        my $glob = PdfCollection::Meta::DEFAULT_BASEDIR
          . "/" . substr($sha1,0,2) . "/$sha1" . "*";
        my ($found) = glob($glob);
        $sha1 = $found if $found;
    }
    return $sha1;
}
