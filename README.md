# PdfCollection

Perl modules and scripts related to maintaining an indexed collection of PDF files.

Assumes some command-line utilities to be available and in the `$PATH`, namely `pdftk`, `pdftotext`, `make` and `zip`.

## Modules

- `PdfCollection::Archiver`: A module for adding pdf files the pdf collection. See also `pdf_archiver.pl` below.
- `PdfCollection::Meta`: Interface to the `meta.yml` (and `notes.md`) associated with each pdf document.
- `PdfCollection::SQLiteFTS`: a module for maintaining a full-text index for the documents in the collection.

## Scripts

- `pdf_archiver.pl`: Adds documents to the collection.
- `pdf_collection_indexer.pl`: Refreshes the full-text index for the collection.
- `pdfcoll_search.pl`: Searches the collection from the command line, using the full-text index.

## Copyright and license

Copyright: Baldur A. Kristinsson, 2015 and later.

All source files in this package, including the documentation, are open source software under the terms of [Perl's Artistic License 2.0](http://www.perlfoundation.org/artistic_license_2_0).
