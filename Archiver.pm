package PdfCollection::Archiver;

use strict;
use locale;
use utf8;
use open qw/:std :utf8/;

use Digest::SHA;
use DateTime;
use File::Copy qw/copy/;
use File::Basename qw/basename/;
use YAML ();
use LWP::UserAgent;
use LWP::Simple;
use JSON qw/decode_json/;
use Text::BibTeX;

use PdfCollection::Meta;
use PdfCollection::SQLiteFTS;

use constant DEFAULT_BASEDIR => $ENV{HOME} . '/pdfcollection';
use constant DEFAULT_META_FILE => 'meta.yml';
# relative to basedir
use constant DEFAULT_MAKEFILE_TEMPLATE => 'bin/Makefile.in';

sub new {
    my ($pk, %opt) = @_;
    my $class = ref($pk) || $pk;
    my $self = \%opt;
    bless($self, $class);
    $self->_init();
    return $self;
}

sub _init {
    my $self = shift;
    $self->{basedir} ||= DEFAULT_BASEDIR;
    $self->{meta_file} ||= DEFAULT_META_FILE;
    $self->{makefile_template} ||= DEFAULT_MAKEFILE_TEMPLATE;
    $self->{makefile_template} = join(
        '/', $self->{basedir}, $self->{makefile_template})
        unless $self->{makefile_template} =~ /^\//;
    $self->{no_fts_index} ||= 0;
}

sub archive {
    # Hardlink/copy pdf file to collection directory,
    # explode it into pages and convert each page into a .txt file.
    # Also, create a meta.yml file with information extracted
    # from the pdf file and/or found based on a detected doi or isbn.
    my ($self, $fn, @info) = @_;
    die "'$fn' is not a PDF file (given the extension)\n" unless $fn =~ /\.pdf$/i;
    my $sha1 = sha1sum($fn);
    return unless $sha1;
    my $subdir = substr($sha1,0,2);
    mkdir $self->{basedir}."/$subdir" unless -d $self->{basedir}."/subdir";
    my $dir = $self->{basedir} . "/$subdir/$sha1";
    mkdir $dir unless -d $dir;
    die "missing targetdir" unless -d $dir;
    my $new_fn = "$dir/$sha1.pdf";
    die "Already exists: $fn => $new_fn [$self->{meta_file}]\n"
        if -f "$dir/$self->{meta_file}";
    my $meta = init_meta($fn, $sha1);
    link($fn, $new_fn) or copy($fn, $new_fn) or die "link/copy failed";
    my ($pages, $doi, $isbn) = pdf_processing($dir, $sha1, $fn);
    unless ($isbn) {
        $isbn = $1 if $fn =~ /isbn(\d{10}(?:\d\d\d)?)/i;
    }
    $meta->{pages} = $pages;
    my @tags = ();
    foreach my $item (@info) {
        if ($item =~ /^\w+: /) {
            my ($k, $v) = split /:\s+/, $item, 2;
            $meta->{$k} = $v;
        }
        else {
            push @tags, $item;
        }
    }
    $meta->{tags} = \@tags if @tags;
    my $renamed = '';
    if ($doi) {
        $renamed = write_doi_info($doi, $meta, $dir, $sha1);
    }
    elsif ($isbn) {
        $renamed = write_isbn_info($isbn, $meta, $dir, $sha1);
    }
    chdir $dir;
    if ($renamed) {
        rename $new_fn, $renamed;
        symlink basename($renamed), basename($new_fn);
        $new_fn = $renamed;
    }
    $meta->{full_path} = $new_fn;
    $meta->{filename} = basename($new_fn);
    my $pdfinfo = get_pdfinfo($new_fn);
    $meta->{pdfinfo} = $pdfinfo if $pdfinfo;
    update_core_info($meta);
    my %auxargs = (
        basedir=>$self->{basedir}, meta_file=>$self->{meta_file});
    my $mo = new PdfCollection::Meta(%auxargs);
    $mo->write_meta($sha1, $meta);
    unless ($self->{no_fts_index}) {
        my $fts = new PdfCollection::SQLiteFTS(%auxargs);
        $fts->index_bundle($meta->{sha1});
    }
    # Do some housekeeping: Add a Makefile to the directory and
    # create a zipfile. Then call make clean so as to remove the
    # temporary pdf and text files.
    link $self->{makefile_template}, "Makefile";
    system("zip $sha1.txt.zip *.page_[0-9][0-9][0-9][0-9].txt");
    system("make clean");
    return $meta;
}


### PLAIN SUBS BELOW

sub update_core_info {
    # Try to set author, title, subtitle, summary, year, keywords
    # in meta (based on bibrec / isbn info)
    my $meta = shift;
    # my @kw = qw/author title subtitle year keywords summary/;
    # my ($author, $title, $subtitle, $year, $keywords, $summary);
    my %chk = ();
    my $bibrec = parse_bibrec($meta->{bibrec});
    my $pdfinfo = $meta->{pdfinfo} || {Creator=>''};
    my $pi_title = '';
    my $pi_author = '';
    # For now, only trust pdfinfo in titles from the Internet Archive
    if ($pdfinfo->{Creator} =~ /Internet Archive/i) {
        $pi_title = $pdfinfo->{Title};
        $pi_author = $pdfinfo->{Author};
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
    $chk{author} = $bibrec->{author} || $aitem->{author} || $pi_author;
    $chk{title} = $bibrec->{title} || $aitem->{title} || $pi_title;
    $chk{subtitle} = $aitem->{subtitle};
    $chk{year} = $bibrec->{year} || $aitem->{year};
    $chk{keywords} = $aitem->{keywords};
    $chk{summary} = $aitem->{summary};
    foreach my $k (keys %chk) {
        $meta->{$k} = $chk{$k} if $chk{$k};
    }
}

sub write_isbn_info {
    my ($isbn, $meta, $dir, $sha1) = @_;
    $meta->{isbn} = $isbn;
    $meta->{isbn_is_auto} = 1;
    my $isbn_info = get_isbn_info($isbn);
    if ($isbn_info) {
        $meta->{isbn_info} = $isbn_info;
        $meta->{isbn_info_source} = "Google Books";
        my $start = substr($sha1, 0, 8);
        return "$dir/isbn$isbn.$start.pdf";
    }
    return;
}

sub write_doi_info {
    my ($doi, $meta, $dir, $sha1) = @_;
    $meta->{doi} = $doi;
    $meta->{doi_is_auto} = 1;
    my ($bibkey, $bibrec) = get_bib($doi);
    if ($bibkey) {
        $meta->{bibkey} = $bibkey;
    }
    if ($bibrec && $bibkey) {
        open OUT, ">:encoding(UTF-8)", "$dir/$bibkey.bib";
        print OUT $bibrec, "\n";
        close OUT;
        my $start = substr($sha1, 0, 8);
        $bibrec =~ s/^\s+//;
        $bibrec =~ s/\s+$//;
        $bibrec =~ s/\n/ /g;
        $meta->{bibrec} = $bibrec;
        return "$dir/$bibkey.$start.pdf";
    }
    return;
}

sub get_bib {
    my $doi = shift;
    my $ua = new LWP::UserAgent;
    $ua->default_header('Accept' => 'text/bibliography; style=bibtex');
    my $resp = $ua->get('http://dx.doi.org/' . $doi);
    return unless $resp->is_success;
    my $bib = $resp->decoded_content;
    my $bibkey = $1 if $bib =~ /^\s*\@[\w\-]+\{([\w\-]+)\s*,/s;
    return ($bibkey, $bib);
}

sub get_isbn_info {
    # gets data from Google Books
    my $isbn = shift;
    my $googlebooks = "https://www.googleapis.com/books/v1/volumes?q=isbn:";
    my $content = get($googlebooks.$isbn);
    return get_otto_isbn_info($isbn) unless $content;
    my $data = decode_json $content;
    if (ref $data eq 'HASH' && $data->{items} && @{$data->{items}}) {
        return $data;
    } else {
        return get_otto_isbn_info($isbn);
    }
}

sub get_otto_isbn_info {
    # fallback: gets data from ottobib.com
    my $isbn = shift;
    my $url = "http://www.ottobib.com/isbn/$isbn/bibtex";
    warn "checking $url\n";
    my $content = get($url);
    my $bibrec = $1 if $content =~ m{<textarea.*?>(.*)</textarea>}s;
    return unless $bibrec;
    my $data = parse_bibrec($bibrec);
    return unless $data;
    $data->{bibrec} = $bibrec;
    return {ottobib=>$data};
}

sub parse_bibrec {
    my $entry_s = shift;
    my $ret = {};
    eval {
        my $entry = new Text::BibTeX::Entry $entry_s;
        my @fields = $entry->fieldlist;
        foreach my $f (@fields) {
            $ret->{$f} = $entry->get($f);
        }
    };
    return if $@;
    return $ret;
}

sub get_pdfinfo {
    my $new_fn = shift;
    my @info = qx/pdfinfo $new_fn/;
    my %ret = ();
    foreach my $ln (@info) {
        chomp $ln;
        next unless $ln =~ /^\w/;
        my ($k, $v) = split /:\s+/, $ln ,2;
        $ret{$k} = $v if $k && $v;
    }
    return \%ret if %ret;
    return;
}

sub pdf_processing {
    my ($dir, $sha1, $orig_fn) = @_;
    chdir $dir;
    system("pdftk", "$sha1.pdf", "burst", "output", "$sha1.page_%04d.pdf");
    my $fc = 0;
    my $doi = undef;
    my $isbn = undef;
    opendir DIR, $dir;
    my @pages = sort grep { /^$sha1.page_\d+\.pdf$/ } readdir DIR;
    closedir DIR;
    foreach my $fn (@pages) {
        my $num = int($1) if $fn =~ /_(\d+)\.pdf$/;
        system("pdftotext", $fn);
        $fc++;
        # don't look for DOI after the first 2 pages;
        # don't look for ISBN after the first 9 pages.
        if ($num < 10 && !($doi || $isbn)) {
            $fn =~ s/\.pdf/\.txt/;
            open IN, $fn;
            while (<IN>) {
                $doi = $1 if $num < 3 && /\bdoi:\s*(\S+)/i;
                last if $doi;
                my $maybe_isbn = $1 if /ISBN(?:10|13)?:? *(\S+)/i;
                if ($maybe_isbn) {
                    $maybe_isbn =~ s/\D//g;
                    $isbn = $maybe_isbn
                        if length($maybe_isbn) == 10 || length($maybe_isbn) == 13;
                }
                last if $isbn;
            }
            close IN;
        }
    }
    # Fallback: check for DOI/ISBN in filename
    unless ($doi) {
        $orig_fn =~ s/%2f/\//gi;
        $doi = $1 if $orig_fn =~ /doi.?(10\.[\w\-\/\.]+)/i;
    }
    unless ($isbn) {
        $orig_fn =~ s/\-//g;
        $isbn = $1 if $orig_fn =~ /isbn\D?(\d{10,13})\b/i;
    }
    closedir DIR;
    unlink "doc_data.txt" if -f "doc_data.txt";
    return ($fc, $doi, $isbn);
}

sub init_meta {
    my ($fn, $sha1) = @_;
    my @stat = stat($fn);
    my $size = $stat[7];
    my $mtime = $stat[9];
    my $ts = DateTime->from_epoch(epoch=>$mtime)->datetime;
    my $now = DateTime->now->datetime;
    $fn =~ s/^.*\///; # strip path
    return {
        original_filename => $fn,
        sha1 => $sha1,
        file_ts => $ts,
        now_ts => $now,
        bytes => $size,
    }
}

sub sha1sum {
    my $fn = shift;
    return unless -f $fn;
    open my $fh, $fn or die "Could not open file for SHA1: $fn\n";
    binmode $fh, qw/:raw/;
    my $sha1 = Digest::SHA->new;
    $sha1->addfile($fh);
    close $fh;
    return $sha1->hexdigest;
}

1;

__END__

=pod

=head1 NAME

PdfCollection::Archiver - archive pdf files in collection

=head1 SYNOPSIS

  use PdfCollection::Archiver;
  my $archiver = new PdfCollection::Archiver;
  $archiver->archive($filename);

=head1 DESCRIPTION

TDB

=head1 SEE ALSO

pdf_archiver.pl

=head1 REQUIREMENTS

TBD

=head1 AUTHOR

Baldur A. Kristinsson, 2015

=cut
