package PdfCollection::SQLiteFTS;

use strict;
use DBI;
use Digest::SHA qw/sha1_hex/;
use PdfCollection::Meta;
use Text::Ligature qw/from_ligatures/;
use File::Slurp qw/read_file/;
use locale;
use utf8;

use constant DEFAULT_BASEDIR => $ENV{HOME} . '/pdfcollection';
use constant DEFAULT_DB_FILE => 'index.sqlite';


sub new {
    my ($pk, %opt) = @_;
    my $class = ref($pk) || $pk;
    my $self = \%opt;
    bless($self, $class);
    $self->_init();
    return $self;
}

sub index_all {
    # Index whole collection; only meta if meta_only opt is true.
    my $self = shift;
    my %opts = @_;
    opendir DIR, $self->{basedir};
    my @subdirs = grep { /^[0-9a-f][0-9a-f]$/ } readdir DIR;
    closedir DIR;
    foreach my $sd (@subdirs) {
        opendir DIR, $self->{basedir}.'/'.$sd;
        my @bundles = grep { /^[0-9a-f]{40}$/ } readdir DIR;
        closedir DIR;
        foreach my $bundle (@bundles) {
            $self->index_bundle($bundle) unless $opts{meta_only};
            $self->index_meta($bundle);
        }
    }
    # optimize and combine b-trees
    if ($self->{_indexed_bundles}) {
        warn "=> Optimizing...\n" if $self->{verbose};
        $self->{dbh}->do("INSERT INTO fts_page(fts_page) VALUES('optimize')");
    }
}

sub index_meta {
    my ($self, $sha1, %opt) = @_;
    $opt{force_update} ||= 0;
    $sha1 =~ s/.*\///; # remove possible leading dir
    my ($dir, $mod_dir, $mod_meta) = $self->_bundleinfo($sha1);
    # before: folder_sha1; after: ts
    my @core_fields = qw(author title subtitle year pages summary);
    my $dbh = $self->{dbh};
    my $rec = $dbh->selectrow_hashref("select * from meta where folder_sha1 = ?", {}, $sha1) || {};
    my $meta = $self->{m}->read_meta($sha1);
    my @meta_bind = ();
    # The primary purpose here is to ensure that author is a scalar
    foreach my $field (@core_fields) {
        push @meta_bind, (
            ref $meta->{$field} eq 'ARRAY'
              ? join(" ; ", @{$meta->{$field}})
              : "$meta->{$field}"
        );
    }
    if (! $rec->{meta_id}) {
        # insert
        warn " - $sha1 (meta - insert)\n" if $self->{verbose};
        my $sql = "insert into meta (folder_sha1, "
            . join(', ', @core_fields)
            . ", ts) values (?, ?,?,?,?,?,?, ?)";
        $dbh->do($sql, {}, $sha1, @meta_bind, $mod_meta);
    }
    elsif ($rec->{ts} < $mod_meta || $opt{force_update}) {
        # update
        warn " - $sha1 (meta - update)\n" if $self->{verbose};
        my $sql = "update meta set "
            . join(' = ?, ', @core_fields)
            . " = ?, ts = ? where meta_id = ? and folder_sha1 = ?";
        $dbh->do($sql, {},
                 @meta_bind, $mod_meta, $rec->{meta_id}, $sha1);
    }
}

sub _bundleinfo {
    # Get directory, its modification time and the mod time of the meta.yml
    my ($self, $sha1) = @_;
    $sha1 =~ s/.*\///; # remove possible directory path
    my $sd = substr($sha1, 0, 2);
    my $dir = join('/', $self->{basedir}, $sd, $sha1);
    unless (-d $dir) {
        warn "WARNING: $dir not found: not indexed\n";
        return;
    }
    # assumes that nothing in directory will change without either
    # adding/removing a file or updating meta.yml
    my $mod_dir = (stat $dir)[9];
    my $mod_meta = (stat "$dir/meta.yml")[9];
    return ($dir, $mod_dir, $mod_meta);
}

sub index_bundle {
    # Index a given directory/SHA1 container
    my ($self, $sha1) = @_;
    my ($dir, $mod_dir, $mod_meta) = $self->_bundleinfo($sha1);
    if ($self->{reftime} > $mod_dir && $self->{reftime} > $mod_meta) {
        return unless $self->{force_update};
    }
    warn "- $sha1\n" if $self->{verbose};
    $self->{_indexed_bundles}++;
    my $need_make = -f "$dir/$sha1.page_0001.txt" ? 0 : 1;
    if ($need_make) {
        chdir $dir;
        system("make");
    }
    opendir DIR, $dir;
    my @files = grep { /page_\d+\.txt$/ } readdir DIR;
    closedir DIR;
    foreach my $f (@files) {
        my $text = read_file("$dir/$f", binmode=>':utf8') or die "Could not read $dir/$f";
        $self->index_page(folder_sha1=>$sha1, file_name=>$f, text=>$text);
    }
    system("make clean") if $need_make;
}

sub _init {
    my $self = shift;
    $self->{force_update} ||= 0;
    $self->{verbose} ||= 0;
    $self->{basedir} ||= DEFAULT_BASEDIR;
    $self->{db_dir} ||= $self->{basedir} . '/var';
    $self->{db} ||= DEFAULT_DB_FILE;
    $self->{db} = $self->{db_dir} .'/' . $self->{db}
        unless $self->{db} =~ /\//;
    my $create = -f $self->{db} ? 0 : 1;
    if ($create) {
        $self->{reftime} = 0;
    }
    else {
        $self->{reftime} ||= (stat $self->{db})[9];
    }
    my @dsn = (
        "dbi:SQLite:dbname=$self->{db}", undef, undef,
        {RaiseError=>1, AutoCommit=>1, sqlite_unicode=>1});
    $self->{dbh} = DBI->connect(@dsn) or die "Could not open database";
    $self->{dbh}->do('pragma encoding = "UTF-8"');
    $self->_create_schema if $create;
    $self->{m} = PdfCollection::Meta->new(
        verbose=>$self->{verbose});
}

sub _create_schema {
    my $self = shift;
    my $dbh = $self->{dbh};
    # folder_sha1 is  is the sha1 key of the parent PDF file
    # page_id is used in lieu of rowid for the fts virtual table
    my @sql = (
        "create table meta (
           meta_id integer primary key,
           folder_sha1 text,
           author text,
           title text,
           subtitle text,
           year int,
           pages int,
           summary text,
           ts int,
           unique(folder_sha1))",
        "create table page (
           page_id integer primary key,
           folder_sha1,
           file_name text,
           unique (file_name))",
        "create virtual table fts_page
          using fts4 (
           file_contents)"
    );
    $dbh->begin_work;
    foreach my $sql (@sql) {
        $dbh->do($sql);
    }
    $dbh->commit;
}

sub index_page {
    # index a single .txt file (which represents a page in a pdf file)
    my $self = shift;
    my $dbh = $self->{dbh};
    my %rec = @_;
    die "need folder_sha1, file_name and text for indexing"
        unless $rec{folder_sha1} && $rec{file_name} && defined($rec{text});
    my $text = $rec{text} || '';
    utf8::upgrade($text);
    $text = $self->_munge_text($text);
    # Only changes affecting the search object matter, so don't store $text directly
    my $page_id = $dbh->selectrow_array(
        "select page_id from page where file_name = ?",
        {}, $rec{file_name});
    return if $page_id && !$self->{force_update};
    $dbh->begin_work;
    if ($page_id) {
        $dbh->do(
            "update fts_page set file_contents = ? where rowid = ?",
            {}, $text, $page_id); 
    }
    else {
        $dbh->do(
            "insert into page (folder_sha1, file_name) values (?, ?)",
            {}, $rec{folder_sha1}, $rec{file_name});
        $page_id = $dbh->last_insert_id("","","","");
        $dbh->do(
            "insert into fts_page (rowid, file_contents) values (?, ?)",
            {}, $page_id, $text);
    }
    $dbh->commit;
}

sub delete_page {
    my $self = shift;
    my %parm = @_;
    my $dbh = $self->{dbh};
    die "need either id or file_name" unless $parm{id} || $parm{file_name};
    if ($parm{file_name} && !$parm{id}) {
        $parm{id} = $dbh->selectrow_array(
            "select page_id from page where file_name = ?",
            {}, $parm{file_name});
        return 0 unless $parm{id};
    }
    my $ret = $dbh->do("delete from page where page_id = ?", {}, $parm{id});
    $dbh->do("delete from fts_page where rowid = ?", {}, $parm{id});
    return int($ret);
}

sub search {
    my ($self, $query, %opt) = @_;
    utf8::upgrade($query);
    my $dbh = $self->{dbh};
    my $meta_res = [];
    if ($opt{search_meta}) {
        $opt{meta_queries} = [$query]
            unless ref $opt{meta_queries} eq 'ARRAY' && @{ $opt{meta_queries} } ;
        my $col_expr = qq[lower(' '||coalesce(author,'')||' '||coalesce(title,'')||' '||coalesce(subtitle, '')||' '||coalesce(summary,'')||' ')];
        my $like_query = join(" OR $col_expr LIKE ",
                              map { $dbh->quote('%'.lc($_).'%') } @{ $opt{meta_queries} });
        my $meta_sql = qq[
          select
            'meta' as type,
            meta_id,
            folder_sha1,
            author,
            title,
            subtitle,
            summary
          from meta
            where $col_expr LIKE $like_query
          order by folder_sha1
        ];
        $meta_res = $dbh->selectall_arrayref($meta_sql,{Columns=>{}});
    }
    my $lquery = $self->_prepare_query($query); # mainly lowercasing
    # TODO: create rank() function taking matchinfo(fts_page) as its
    # material, and order by that
    my $sql = qq[
      select
        'fts' as type,
        a.page_id,
        a.folder_sha1, 
        a.file_name,
        snippet(fts_page) as snippet,
        offsets(fts_page) as offsets
      from page a join fts_page b
        on a.page_id = b.rowid
      where fts_page match ?
      order by 2, 3
    ];
    my $res = $dbh->selectall_arrayref($sql, {Columns=>{}}, $lquery);
    return [@$meta_res, @$res];
}

sub _prepare_query {
    # "standard" FTS syntax, not "enhanced"
    my ($self, $query) = @_;
    return my_lc($query) unless $query =~ / (?:OR|AND) /;
    my $lquery = '';
    while ($query) {
        if ($query =~ s/^(OR|AND)\s+//) {
            # keep OR, omit AND
            $lquery .= "$1 " unless $1 eq 'AND';
        }
        elsif ($query =~ s/\s*(\S+)\s+//) {
            $lquery .= my_lc($1)." ";
        }
        else {
            $lquery .= $query;
            last;
        }
    }
    $lquery =~ s/ $//;
    warn "returning query='$lquery'\n";
    return $lquery;
}

sub my_lc {
    # TODO: Detect which lower casing method is appropriate
    # given the current environment.
    #
    # This REQUIRES use utf8 and use locale in a UTF-8 environment:
    my $s = shift;
    return lc($s);
    # This is not appropriate with 'use utf8' and 'use locale':
    #$s =~ tr/A-ZÁÉÍÓÚÝÞÆÖÐØÅ/a-záéíóúýþæöðøå/;
    #return $s;
}

sub _munge_text {
    my ($self, $txt) = @_;
    $txt =~ s{<script.*</script>}{}sg;
    $txt =~ s{<style.*</style>}{}sg;
    $txt =~ s{<[^>]*>}{ }g;
    $txt =~ s{\s+}{ }g;
    $txt =~ s{^ }{};
    $txt =~ s{ $}{};
    $txt =~ s{\&(\d+);}{chr($1)}ge;
    $txt =~ s{\&x([a-fA-F0-9]+);}{chr(hex($1))}ge;
    $txt =~ s{(\S)\-\n\r?\s*([a-z])}{$1$2}g;
    $txt = from_ligatures($txt);
    return my_lc($txt);
}

1;
