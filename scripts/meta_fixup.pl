#!/usr/bin/env perl

use strict;
use PdfCollection::Meta;
use YAML qw/Dump/;
use Text::BibTeX;
use Term::ReadKey qw/ReadMode ReadKey/;

my @meta_fns = @ARGV;
die qq{Usage: $0 sha1_or_meta_file1 [sha1_or_meta_file2 ...]

Tries to find author, title and a few other pieces of information
and put them into standard fields in the meta file (if they are missing).
Asks for confirmation before writing any changes.
} unless @meta_fns;

ReadMode 3;

my $m = new PdfCollection::Meta;

foreach my $fn (@meta_fns) {
    my $sha1 = $1 if $fn =~ /([a-f0-9]{40})/;
    unless ($sha1) {
        warn "Could not find sha1 in $fn - skipping\n";
        next;
    }
    eval {
        my $meta = $m->read_meta($sha1); # meta is a hashref
        my $have = '';
        foreach (qw/author title year/) {
            $have .= " $_=$meta->{$_}" if $meta->{$_};
        }
        my $add = get_add($meta);
        unless ($add) {
            print "=> NOTHING FOUND FOR $fn -- skipping";
            print "-------\n";
            next;
        }
        my $key = undef;
        if ($ENV{META_AUTO_WRITE_FIELD} && $add->{$ENV{META_AUTO_WRITE_FIELD}}) {
            $key = 'y';
            print "=> AUTOWRITING $fn\n";
        }
        elsif ($ENV{META_SKIP_NONAUTO}) {
            $key = 'n';
            print "=> AUTOSKIPPING $fn\n";
        }
        else {
            print Dump($add);
            print "\nALREADY HAVE: $have" if $have;
            print "\nKeep these changes? (Y/N) ";
            while (not defined ($key = ReadKey(-1))) {
                # just wait...
            }
            print "\n";
        }
        if ($key eq 'Y' || $key eq 'y') {
            my $status = $m->edit_meta($sha1, $add);
            print "=> WROTE $fn\n";
        } else {
            print "=> NOT WRITING $fn\n";
        }
        print "-------\n";
    };
    if ($@) {
        warn "WARNING: meta edit for $fn failed: $@\n";
        next;
    }
}

ReadMode 0;

############# sub below ########


sub get_add {
    my $meta = shift;
    my %add = ();
    # my @kw = qw/author title subtitle year keywords summary/;
    # my ($author, $title, $subtitle, $year, $keywords, $summary);
    my %chk = ();
    my $bibrec = get_bibrec($meta->{bibrec});
    my $pdfinfo = $meta->{pdfinfo} || {};
    for my $k (qw/Author Title/) {
        $pdfinfo->{$k} = undef if $pdfinfo->{$k} && $pdfinfo->{$k} =~ /8=8/;
    }
    my @aitems = ();
    if ($meta->{isbn_info} && $meta->{isbn_info}->{items}) {
        foreach my $outer (@{ $meta->{isbn_info}->{items} }) {
            my $it = $outer->{volumeInfo} || {};
            my $rec = {};
            if ($it->{authors}) {
                $rec->{author} = ref $it->{authors} eq 'ARRAY' && @{$it->{authors}}==1 ? $it->{authors}->[0] : $it->{authors};
            } elsif ($it->{author}) {
                $rec->{author} = $it->{author};
            }
            $rec->{title} = $it->{title} if $it->{title};
            $rec->{subtitle} = $it->{subtitle} if $it->{title};
            $rec->{year} = $it->{publishedDate} if $it->{publishedDate};
            $rec->{keywords} = $it->{categories} if $it->{categories};
            $rec->{summary} = $it->{description} if $it->{description};
            push @aitems, $rec if keys %$rec;
        }
    }
    elsif ($meta->{isbn_info}->{ottobib}) {
        push @aitems, $meta->{isbn_info}->{ottobib};
    }
    my $aitem = $aitems[0] || {};
    $chk{author} = $bibrec->{author} || $aitem->{author} || $pdfinfo->{Author};
    $chk{title} = $bibrec->{title} || $aitem->{title} || $pdfinfo->{Title};
    $chk{subtitle} = $aitem->{subtitle};
    $chk{year} = $bibrec->{year} || $aitem->{year};
    $chk{keywords} = $aitem->{keywords};
    $chk{summary} = $aitem->{summary};
    foreach my $k (keys %chk) {
        $add{$k} = $chk{$k} if $chk{$k};
    }
    return %add ? \%add : undef;
}

sub get_bibrec {
    my $entry_s = shift;
    my $ret = {};
    return $ret unless $entry_s;
    eval {
        my $entry = new Text::BibTeX::Entry $entry_s;
        my @authors = $entry->split('author');
        if (@authors) {
            $ret->{author} = (@authors>1 ? \@authors : $authors[0]);
        }
        my $title = $entry->get('title');
        $ret->{title} = $title if $title;
        my $year = $entry->get('year');
        $ret->{year} = $1 if $year =~ /((?:17|18|19|20)\d\d)/;
    };
    return $ret;
}
