package PdfCollection::Meta;
use YAML qw/Load Dump/;
use File::Slurp qw/read_file write_file/;

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
    warn "writing meta: $fn\n";
    return write_file($fn, {atomic=>1, binmode=>':utf8'}, Dump($meta));
}

sub edit_meta {
    # Adds or changes a set of keys in meta, then writes the
    # changed entry
    my ($self, $sha1, $add) = @_;
    die "The second argument to edit_meta should be a hashref"
        unless ref $add eq 'HASH';
    my $meta = $self->read_meta($sha1);
    foreach $k (keys %$add) {
        $meta->{$k} = $add->{$k};
    }
    return $self->write_meta($sha1, $meta);
}

sub get_notes {
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

  $m = new PdfCollection::Meta;

  $meta = $m->read_meta($sha1); # meta is a hashref

  $status = $m->write_meta($sha1, $meta);

  # $add contains new or changed keys
  $status = $m->edit_meta($sha1, $meta, $add);

=head1 AUTHOR

Baldur A. Kristinsson, 2015

=cut
