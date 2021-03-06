package PdfCollection::Meta;

use strict;
use YAML qw/Load Dump/;
use File::Slurp qw/read_file write_file/;
use Text::Unidecode qw/unidecode/;

use constant DEFAULT_BASEDIR => $ENV{HOME} . '/pdfcollection';
use constant DEFAULT_META_FILE => 'meta.yml';
use constant DEFAULT_NOTES_FILE => 'notes.md';

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
    $self->{notes_file} ||= DEFAULT_NOTES_FILE;
    $self->{verbose} ||= 0;
}

sub expand_sha1 {
    # Expands a shortened sha1 into the full 40 characters.
    # Utility method: not used internally.
    my ($self, $shortened_sha1) = @_;
    if (length($shortened_sha1) < 40 && length($shortened_sha1) > 4) {
        my $glob = $self->{basedir}
          . "/" . substr($shortened_sha1, 0, 2)
          . "/$shortened_sha1" . '*';
        my ($found) = glob($glob);
        return $1 if $found && $found =~ /\b([a-f0-9]{40})\b/;
    }
    return $shortened_sha1;
}

sub read_meta {
    # reads a meta file and returns the contents as a hashref
    my ($self, $sha1) = @_;
    my $fn = $self->_meta_path($sha1, 1);
    my $fc = read_file($fn, {binmode=>':utf8'});
    return Load($fc);
}

sub write_meta {
    # Writes a complete meta entry
    my ($self, $sha1, $meta) = @_;
    my $fn = $self->_meta_path($sha1, 0);
    warn "writing meta: $fn\n" if $self->{verbose};
    return write_file($fn, {atomic=>1, binmode=>':utf8'}, Dump($meta));
}

sub edit_meta {
    # Adds or changes a set of keys in meta, then writes the
    # changed entry
    my ($self, $sha1, $add) = @_;
    die "The second argument to edit_meta should be a hashref"
        unless ref $add eq 'HASH';
    my $meta = $self->read_meta($sha1);
    foreach my $k (keys %$add) {
        warn "Adding $k to meta\n" if $self->{verbose};
        $meta->{$k} = $add->{$k};
    }
    return $self->write_meta($sha1, $meta);
}

sub get_slug {
    my ($self, $sha1, %opt) = @_;
    my $meta = $self->read_meta($sha1);
    my $save = $opt{save};
    # Return a manual slug if it exists and is not being overwritten
    if ($meta->{slug}) {
        $save = $opt{overwrite} if $save;
        return $meta->{slug} unless $save;
    }
    # Assemble the elements for the automatic slug
    my $author = _slugify($meta->{author});
    my $title = _slugify($meta->{title});
    my $year = $1 if $meta->{year} && $meta->{year} =~ /(\d{4})/;
    my $bibkey = $meta->{bibkey};
    $bibkey =~ s/\W/-/g if $bibkey;
    my $partial_sha = substr($sha1, 0, 7);
    # Construct, (possibly) save and return the slug
    my $slug = join(
        '_',
        grep {$_} $author, $title, $year, $bibkey, $partial_sha);
    $self->set_slug($sha1, $slug) if $save;
    return $slug;
}

sub _slugify {
    # cleans a string (or arrayref of strings) in preparation
    # for using it as part of a slug.
    my ($s, $len) = @_;
    return '' unless $s;
    if (ref $s eq 'ARRAY') {
        $s = join(' ', @$s);
    }
    $len ||= 30;
    $s = lc(unidecode($s));
    $s =~ s/\s+/-/g;
    $s =~ s{[^a-z0-9]}{-}g;
    $s =~ s{\-\-+}{-}g;
    $s =~ s/^\-//;
    $s =~ s/\-$//;
    return length($s) < $len ? $s : substr($s, 0, $len);
}

sub set_slug {
    my ($self, $sha1, $slug) = @_;
    return $self->edit_meta($sha1, {slug=>$slug});
}

sub get_notes {
    die "TBD: get_notes not implemented yet\n";
    # NB: no write_notes() method
}

sub _meta_path {
    my ($self, $sha1, $must_exist) = @_;
    return $self->_path($sha1, 'meta_file', $must_exist);
}

sub _notes_path {
    my ($self, $sha1, $must_exist) = @_;
    return $self->_path($sha1, 'notes_file', $must_exist);
}

sub _path {
    my ($self, $sha1, $key, $must_exist) = @_;
    die "Invalid key: $key"
        unless $key eq 'meta_file' || $key eq 'notes_file';
    if ($sha1 =~ /\b([a-f0-9]{40})\b/) {
        $sha1 = $1;
    } else {
        die "BAD SHA1: $sha1";
    }
    my $path = join('/', $self->{basedir}, substr($sha1,0,2), $sha1, $self->{$key});
    if ($must_exist) {
        die "FILE NOT FOUND: $path" unless -e $path;
    }
    return $path;
}

1;

__END__

=pod

=head1 NAME

PdfCollection::Meta - interface to pdfcollection meta.yml (and notes.md)

=head1 SYNOPSIS

  use PdfCollection::Meta;

  $m = PdfCollection::Meta->new(verbose=>1);

  $meta = $m->read_meta($sha1); # meta is a hashref

  $status = $m->write_meta($sha1, $meta);

  # $add is a hashref containing new or changed keys
  $status = $m->edit_meta($sha1, $add);

  # Slug is either set manually or automatic and based on author, title,
  # year and sha1.
  # If save is true, it will be saved to the meta file if missing.
  # If overwrite is true, it will be written even if already present.
  #
  $slug = $m->get_slug($sha1, save=>1, overwrite=>1);

=head1 AUTHOR

Baldur A. Kristinsson, 2015

=cut
