# latest_books.pl

If you're a frequent library user, you might go online to your library's
public website and search for new books available from your favorite 
authors.  If your list of favorite authors is long, that's a tedious task.  

This script can make that task easier by determining whether the library
has any publications available this year for those authors.

That information is obtained for each author in a configured list by 
going to the library website, searching for that author, scraping the 
information from the web page, and filtering it for books published 
in the current year. 

Unfortunately, there are several different types of online catalog systems
(some open source), and different releases of those systems.  This script 
works with iPAC (Internet Public Access Catalog) version 2.0 and 
Horizon Information Portal 3.23_6380.  A newer version of the portal
appears to work with the exception of sorting by media types, as the 
media codes and types are different.

Additionally, the web page produced by the online catalog system
doesn't use ids, classes or much other useful HTML identifiers for the 
section that contains book information.  As a result, this script is 
vulnerable when changes or updates are made to the library's web page.

If nothing else, this script serves as a template that can be modified
by other programmers to work with their favorite library and the online
system that it uses.

## Installation

To install into your ~/bin directory, specify "PREFIX=~" as shown below.

```
perl Makefile.PL PREFIX=~
make 
make test
make install
```

Next, modify the default configuration file, latest_books.conf, which is
found in the same bin install directory.  In particular, the LibraryURL 
and Author values must be edited to specify the appropriate library and 
author list.

Alternatively, copy the configuration file and store it in a different 
directory, then do your edits.  When running the script, specify the 
new path and name of the configuration file using the '-c' option.

### Prerequisites

Currently, Perl version 5.16 or later is required to run the script
because that's the version used in testing.  It's possible earlier 
versions (5.12 and up) will work.  

* URI
* Web::Scraper
* Config::General
* Getopt::Std
* POSIX
* Try::Tiny
* File::Spec
* File::Basename
* Data::Dumper
* Test::More
* Test::Output

## Usage

```
Usage:  ./latest_books.pl  [-v] [-s] [-d] [-c config_filename]

   -v    View the processed contents of the configuration file.
   -s    Sort by media type; only if allowed by online catalog.
         If connection or search fails, try without this option.
   -d    Debug mode - prints the full URL query and any data 
         received back from the query.
   -c    Specifies an alternative configuration file; the default
         file is './latest_books.conf
```

The default configuration file is latest_books.conf and is assumed
to be in the same directory as the script.  It should be modified
to list the authors that you want to track.

## Limitations/TODO 

The script is only guaranteed to work with iPAC version 2.0 and 
Horizon Information Portal 3.23_6380.  Other versions of the portal
or other online library systems may work to some degree or may not.

1.  The script could be made more complicated and more useful by 
    customizing the library query to the version of the online library
    system in use.  That version could be specified in the configuration 
    file.  The query values that would change include:
    * the media codes and types,
    * the publication date order (newest first, e.g., "&sort=310014" or
      "&sort=310013"),
    * the index value (.AW appears to work in most places, but on at 
      least one site, PAUTH was the required index value).
    I'm not sure how many online library system versions are prevalent 
    and how big of a task this would be.

2.  The number of publications listed on a page appear to be 10, at a
    minimum.  The assumption has been made that this is sufficient to 
    find all the publications for the current year.  It would be more
    robust to check and if all of the publications on the page are for
    this year and another page of listings is available, to obtain the
    next page for more publications.  The gotcha is that the query 
    parameter for "next page" is not consistent among online library 
    systems.
