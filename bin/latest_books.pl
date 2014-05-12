#!/usr/bin/perl 
#==============================================================================
#
# latest_books.pl
#
# If you're a frequent library user, you might go online to your library's
# public website and search for new books available from your favorite 
# authors.  If your list of favorite authors is long, that's a tedious task.  
#
# This script can make that task easier by determining whether the library
# has any publications available this year for those authors.
#
# That information is obtained for each author in a configured list by 
# going to the library website, searching for that author, scraping the 
# information from the web page, and filtering it for books published 
# in the current year. 
#
# Unfortunately, there are several different types of online catalog systems
# (some open source), and different releases of those systems.  This script 
# works with iPAC (Internet Public Access Catalog) version 2.0 and 
# Horizon Information Portal 3.23_6380.  A newer version of the portal
# appears to work with the exception of sorting by media types, as the 
# media codes and types are different.
#
# Additionally, the web page produced by the online catalog system
# doesn't use ids, classes or much other useful HTML identifiers for the 
# section that contains book information.  As a result, this script is 
# vulnerable when changes or updates are made to the library's web page.
# 
# If nothing else, this script serves as a template that can be modified
# by other programmers to work with their favorite library and the online
# system that it uses.
#
# Usage:  ./latest_books.pl  [-v] [-s] [-d] [-c config_filename]
#
#    -v    View the processed contents of the configuration file.
#    -s    Sort by media type; only if allowed by online catalog.
#          If connection or search fails, try without this option.
#    -d    Debug mode - prints the full URL query and any data 
#          received back from the query.
#    -c    Specifies an alternative configuration file; the default
#          file is './latest_books.conf'.
#
#===============================================================================

use strict;
use warnings;
use 5.016;

use URI;
use Web::Scraper qw(Scraper);
use Config::General qw(ParseConfig);
use Getopt::Std;                        # core module
use POSIX qw(strftime);                 # core module
use Try::Tiny;
use File::Spec;
use File::Basename;
use Data::Dumper;                       # core module

our $VERSION = '0.01';

# ==========================================================================
# Constants representing the default config file, default media type, the
# list of media types, and the current year.
# ==========================================================================
my $DEFAULT_CONFIG = File::Spec->catfile(
                          dirname(File::Spec->rel2abs(__FILE__)),
                          'latest_books.conf');
my $DEFAULT_MEDIA = 'BOOK';

# --------------------------------------------------------------------------
# The following media codes work for Horizon Information Portal 3.23_6380, 
# but it appears they were all changed for version 3.23_6390.  And they
# could change again.
# 
my %material_types = (
 'BOOK'   => { 'type' => 'IT01', 'code' => 'it_BOOK' },   #BOOK'S
 'ABOOK'  => { 'type' => 'CO01', 'code' => 'gp_ABOOK' },  #ADULT BOOKS
 'EBOOK'  => { 'type' => 'CO01', 'code' => 'co_EBOOK' },  #E-BOOKS
 'ANONB'  => { 'type' => 'CO01', 'code' => 'gp_ANONB' },  #ADULT NON-BOOK
 'CDBK'   => { 'type' => 'CO01', 'code' => 'gp_CDBK' },   #AUDIOBOOKS
 'PAB'    => { 'type' => 'IT01', 'code' => 'it_PAB' },    #PORTABLE AUDIOBOOKS
 'EAUDIO' => { 'type' => 'CO01', 'code' => 'co_EAUDIO' }, #DOWNLOADABLE E-AUDIO 
 'CD'     => { 'type' => 'IT01', 'code' => 'it_CD' },     #CD'S
 'DVD'    => { 'type' => 'IT01', 'code' => 'it_DVD' },    #DVD'S
 'CHBK'   => { 'type' => 'CO01', 'code' => 'gp_CHBK' },   #CHILDREN'S BOOKS
 'CHNFBK' => { 'type' => 'CO01', 'code' => 'gp_CHNFBK' }, #CHILDREN'S NONFIC 
 'LP'     => { 'type' => 'CO01', 'code' => 'gp_LP' },     #LARGE PRINT BOOKS
);

# --------------------------------------------------------------------------
# Publication dates specify the year, so that's the level of granularity we 
# can have to work with.
#
my $year = strftime("%Y", localtime);

# --------------------------------------------------------------------------
# Debug switch - useful to have globally.
#
my $debug = 0;

# ==========================================================================
# usage - Print usage information.
#
# Returns:  Nothing.
# ==========================================================================
sub usage
{
    warn "Usage:  $0  [-v] [-s] [-d] [-c config_filename]\n\n";
    warn "   -v    View the processed contents of the configuration file.\n";
    warn "   -s    Sort by media type; only if allowed by online catalog.\n" .
         "         If connection or search fails, try without this option.\n";
    warn "   -d    Debug mode - prints the full URL query and any data \n" .
         "         received back from the query.\n";
    warn "   -c    Specifies an alternative configuration file; the default\n" .
         "         file is './latest_books.conf'.\n\n";

    return;
}

# ==========================================================================
# scrape - Issue the web query and return the relevant information in a hash.  
#
# The web scraper returns the information in a hash with fields that we 
# pre-defined based on the structure of the web page content.  The hash 
# fields are as follows:
#
# $author_summary = 
# {
#     'summary' =>    [ 
#                         {
#                           'book_info' => [ ... ]
#                         },
#                         {
#                            'book_info' => [ ... ]
#                         }
#                     ],
# };
#
# 'summary' is an array of hashes containing information on each publication.  
# Each hash in the 'summary' array consists of a single array, 'book_info',  
# that contains lines of information about a publication.  (Based on the 
# web page content, I couldn't find a way to eliminate the hash and just 
# have an array of 'book_info' arrays.)
#
# 'book_info' contains one entry that appears to be a summary of all 
# the succeeding entries, two entries contain the title and author's name, 
# one containing just the book title, another containing the publication date, 
# others contain call data, etc.
#
# Returns:  A reference to a hash containing 'summary'.
# ==========================================================================
sub scrape
{
    my ($liburl) = @_;

    # ------------------------------------------------------------------
    # Using XPATH, specify where we intend to find the information on
    # the web page.  In this case, the list is in a deeply nested set of 
    # tables that mostly have no IDs or special characteristics.  This 
    # makes the resulting XPATH very vulnerable to site changes or 
    # differences in site versions.
    #
    my $lib_search = 
        scraper 
        {
            process '//body/center[1]/table[2]/tr/td/table', 'summary[]' => 
            scraper 
            {
                process 'tr/td[2]/table/tr/td', 'book_info[]' => 'TEXT'; 
            };
        };
    warn "URL:  $liburl\n" if ($debug);

    my $author_summary;
    try
    {
        # ------------------------------------------------------------------
        # Could not figure out a way to pass the 'http' scheme and get
        # the proper number of forward slashes to follow it.  The following 
        # alternative works, but seems klunky.
        #
        $liburl = 'http://' . $liburl unless $liburl =~ m/^https?:\/\//ix;
        $author_summary = $lib_search->scrape(URI->new($liburl));
    }
    catch
    {
        # ------------------------------------------------------------------
        # If the liburl is bad, there's no point in continuing.  Provide
        # the error message from scraper, but get rid of the line number as
        # the user doesn't need it.
        # 
        s/\s+at     # line number of error from scrape's die()
          \s+$0
          \s+line
          \s+\d+
         //x;   
        my $errmsg = "ERROR:  Library URL is invalid:\n\t$_\n";
        die $errmsg;
    };

    print Dumper($author_summary->{summary}) if ($debug);
    return ($author_summary);
}

# ==========================================================================
# print_author - Prints author's name and all the publications for this
# year, ignoring titles based on the 'Ignore' configuration option.
#
# Returns:  Nothing; results are sent to stdout.
# ==========================================================================
sub print_author
{
    my ($author, $author_summary_hashref, $ignore_array_ref) = @_;

    # ------------------------------------------------------------------
    # Create a shortcuts into the web scraped results.
    #
    my @books = @{$author_summary_hashref->{summary}};

    # ------------------------------------------------------------------
    # Loop through the titles and print just those publications for this 
    # year.  
    #
    print("$author\n");

    for (my $idx = 0; $idx < scalar(@books); $idx++)
    {
        my $title = $books[$idx]->{book_info}->[2];

        # --------------------------------------------------------------
        # Depending upon the online catalog system, the publication 
        # information can be in row 4 or 5.  If row 4 contains the
        # author information, i.e., "by xxx yyy", then the publication
        # information is in row 5.
        #
        my $publication_info = $books[$idx]->{book_info}->[4];
        if ($publication_info =~ /^by\ /x)
        {
            $publication_info = $books[$idx]->{book_info}->[5];
        }

        # --------------------------------------------------------------
        # The title line also lists the author name, so strip the name
        # off.  Also, strip off the odd question mark "\x{a0}" sometimes 
        # appears at the end of the title.
        #
        $title =~ s/\s*\/         # slash
                    \s*(by\s)?    # optional 'by '
                    \Q$author\E   # author's name with spaces, periods
                    \.?           # possible trailing period
                   //x;
        $title =~ s/\x{a0}    # hex for a symbol of a '?' in a black circle
                    \*$       # don't know why it's followed by an '*'
                   //x;

        # --------------------------------------------------------------
        # The default order of books (at least for the tested version of
        # the online library system) is newest to oldest, so once we 
        # hit a different date, we're done listing books.
        #
        last if ($publication_info !~ /$year/x);

        # --------------------------------------------------------------
        # Compare the title against the list of titles we've been 
        # requested to ignore.  Set a flag if we find a match.
        #
        my $skip_title = 0;
        foreach my $ignored_title (@{$ignore_array_ref})
        {
            if ($title =~ /\Q$ignored_title/ix)
            {
                $skip_title = 1;
                last;
            }
        }

        # Print the title unless it's been flagged as 'ignore'd. 
        print("\t$title\n") unless $skip_title;
    }

    print("\n");
    return;
}

# ==========================================================================
# process_webpage - For each author, build the query for the web page based 
# on the configuration and then invoke scrape() to do the extraction and 
# print_author() to print the results. 
#
# Returns:  Nothing - results are printed through a call to print_author().
# ==========================================================================
sub process_webpage
{
    my ($baseurl, $default_media_type, $authors_array_ref, $sort_option) = @_;

    my $default_media_ref = $material_types{$default_media_type};
    my $author_fullname;

    # ----------------------------------------------------------------------
    # For each author, build the appropriate query using the author name,
    # and media type requested.
    #
    foreach my $author_hash_ref (@{$authors_array_ref})
    {
        my %author = %{$author_hash_ref};
        my $media_ref = $default_media_ref;
        my $liburl = "$baseurl?";

        # ------------------------------------------------------------------
        # If there's a specific media type for this author, use that instead
        # of the default.
        #
        if (exists($author{'MediaType'})) 
        {
            my $media_type = uc($author{'MediaType'});
            $media_ref = $material_types{$media_type};
        }

        # ------------------------------------------------------------------
        # If the command line option for 'sort' was specified, add the 
        # media type and code to the query.  Otherwise, just add the 
        # author's name.  The name order is last name, then first name.
        #
        if ($sort_option)
        {
            $liburl .= "limitbox_1=";
            $liburl .= "$media_ref->{'type'}+%3D+$media_ref->{'code'}&";
        }
        $liburl .= "profile=adm-ada&index=.AW&term=";  # term is author's name

        $author_fullname = "$author{'LastName'},$author{'FirstName'}";
        $liburl .= $author_fullname;

        # ------------------------------------------------------------------
        # If the configuration file indicated that certain titles were to
        # be ignored, make sure we have an array of those titles to pass
        # to scrape().
        #
        my $ignore_array_ref;
        if (exists($author{'Ignore'}))
        {
            $ignore_array_ref = (ref($author{'Ignore'}) eq 'ARRAY') ?
                $author{'Ignore'} :  [$author{'Ignore'}];
        }

        # ------------------------------------------------------------------
        # Issue the query and print the results, ignoring any titles 
        # specified in the configuration.
        #
        my $author_summary_hashref = scrape($liburl);

        # ------------------------------------------------------------------
        # If the web scrap was successful, print the results.
        #
        if (%{$author_summary_hashref} && 
            exists($author_summary_hashref->{summary})) 
        {
            print_author("$author{'FirstName'} $author{'LastName'}",
                $author_summary_hashref, 
                $ignore_array_ref);
        }
        else
        {
            warn "WARNING:  Manual search required.  Either the author " .
                 "isn't in the catalog,\n" .
                 "          or the search returned a list of authors versus " .
                 "a list of books,\n" .
                 "          or the web page is not as expected.\n" .
                 "Skipping '$author_fullname'\n\n";
        }

        # ------------------------------------------------------------------
        # Out of courtesy to the website, wait just a bit before issuing 
        # the next request.
        #
        sleep(2);
    }

    return;
}

# ==========================================================================
# config_ok - Check that the configuration file makes sense:
#     * A library URL must be specified.
#     * Warn if the library URL isn't an ipac20 site.
#     * If a default media type is specified, it must be a valid type.
#     * If a media type is specified for an author, it must be valid.
#     * For each author, a first and last name must be specified.  
#
# Processes all errors in the config file, i.e., processing continues even
# after an error is found.  Error messages are printed to stderr and a
# return value indicates whether an error is found.
#
# Returns: 1 if configuration is ok, 0 if not.
# ==========================================================================
sub config_ok
{
    my ($baseurl, $media_type, $authors_array_ref) = @_;

    # ----------------------------------------------------------------------
    # We use warn() to print out the errors as we want to process all of
    # the errors in the config file, then die.
    #
    my $no_errors = 1;

    # ----------------------------------------------------------------------
    # A library URL must be specified in the configuration file.
    #
    if (!defined($baseurl) || length($baseurl) == 0)
    {
        warn "ERROR:  Library URL missing from configuration file.\n";
        $no_errors = 0;
    }

    # ----------------------------------------------------------------------
    # The script has been tested against library sites using ipac20 and
    # ipac.jsp -- there are no guarantees for any other sites.  Let the 
    # user try the URL, but warn that it most likely won't work.
    #
    if ($baseurl !~ m{ipac20/ipac.jsp$}ix)
    {
        warn "WARNING:  Library URL does not end in 'ipac20/ipac.jsp'.\n" .
             "          iPAC 20 and Horizon Information Portal 3.23_63xx " .
             "systems are\n" .
             "          expected to work; other systems are untested.\n";
        # Don't set $no_errors because this is a true warning, not an error.
    }

    # ----------------------------------------------------------------------
    # We should have a default media type and it must be a valid type.
    #
    if (!defined($media_type) || length($media_type) == 0)
    {
        # This should never happen unless $DEFAULT_MEDIA is accidently deleted.
        warn "PROGRAMMING ERROR:  MediaType missing from configuration file.\n";
        $no_errors = 0;
    }
    elsif (!exists($material_types{$media_type}))
    {
        warn "ERROR:  Bad MediaType ('$media_type') in configuration.\n";
        $no_errors = 0;
    }

    # ----------------------------------------------------------------------
    # Each author should have a first and last name specified.  If a media
    # type is specified for an author, it must be valid.
    #
    foreach my $author_hash_ref (@{$authors_array_ref})
    {
        my %author = %{$author_hash_ref};

        my $no_lastname = !exists($author{'LastName'}) || 
            (length($author{'LastName'}) == 0);

        my $no_firstname = !exists($author{'FirstName'}) || 
            (length($author{'FirstName'}) == 0);

        my $errmsg;
        if ($no_lastname)
        {
            $errmsg = "ERROR:  Configuration missing last name for ";
            $errmsg .= (!$no_firstname) ? 
                        "'$author{'FirstName'}'" : "an author";
            warn "$errmsg.\n";
            $no_errors = 0;
        }

        if ($no_firstname)
        {
            $errmsg = "ERROR:  Configuration missing first name for ";
            $errmsg .= (!$no_lastname) ? 
                        "'$author{'LastName'}'" : "an author";
            warn "$errmsg.\n";
            $no_errors = 0;
        }

        if (exists($author{'MediaType'})) 
        {
            my $author_media_type = uc($author{'MediaType'});
            if (!exists($material_types{$author_media_type}))
            {
                my $name = $no_firstname ? '' : "$author{'FirstName'} ";
                $name .= $no_lastname ? ' ' : $author{'LastName'};

                warn "ERROR:  Bad MediaType ('$author_media_type') in " .
                     "configuration for '$name'\n";
                $no_errors = 0;
            }
        }
    }

    return $no_errors;
}

# ==========================================================================
# get_config - Given an argument of a configuration filename, if one was 
# provided on the command line.  Reads that configuration file or the
# default using Config::General->ParseConfig.  ParseConfig() dies if can't 
# find or read the config file, or if it finds syntax errors.  We'll catch 
# the failure, clean up the error message a bit and die ourself.
#
# Returns - contents of the configuration file in a hash reference.
# ==========================================================================
sub get_config
{
    my ($optional_filename) = @_;

    my $config_filename = $optional_filename // $DEFAULT_CONFIG;
    my %config;
    
    try
    {
        %config = ParseConfig($config_filename);
    }
    catch
    {
        # ------------------------------------------------------------------
        # Clean up the Config::General error message from ParseConfig -- the
        # user doesn't need to know the module name or the line in this
        # file where the error occured.
        #
        s/Config::General
          \s*:?\s*  # a ':' doesn't always follow the package name
         //x;
        s/\s+at     # at
          \s+$0     # program name
          \s+line   # followed by line number.
          \s+\d+\.
         //x;   
        my $errmsg = "ERROR:  $_";

        # ------------------------------------------------------------------
        # If they didn't request a specific configuration, remind them
        # that the default configuration file is in play and may not have
        # been properly customized.
        #
        unless (defined($optional_filename))
        {
            $errmsg .= "        Default configuration file not found.\n";
        }

        die $errmsg;
    };

    return \%config;
}

# ==========================================================================
# Process command line arguments and config file, then invoke the function
# to handle the web scrapes.
# ==========================================================================
sub main
{
    # ----------------------------------------------------------------------
    # Process command line arguments.  Conditions where we want to print a 
    # usage statement:
    #    * when a -c is not followed by a configuration filename,
    #    * for the -h (help) option,
    #    * when an invalid option is given.
    #
    my %opts;
    my $have_valid_options = getopts('dshvc:', \%opts);

    if ((exists($opts{'c'}) && !defined($opts{'c'})) || 
         exists($opts{h}) ||
         !$have_valid_options)
    {
        usage();
        exit(1);
    }

    $debug = $opts{'d'} // 0;           # $debug has file scope
    my $sort_option = $opts{'s'} // 0;

    # ----------------------------------------------------------------------
    # Process the config file, extracting the library URL and list of 
    # authors.  If there's an error 
    #
    my $config_hashref = get_config($opts{'c'});

    # ----------------------------------------------------------------------
    # If the user only wants to view the config file and not process it, 
    # we're done.  Dump the contents and exit.
    #
    if (exists($opts{'v'}))
    {
        print Data::Dumper->Dump([$config_hashref], ["*config"]);
        return;
    }

    # ----------------------------------------------------------------------
    # If the user hasn't specified any authors in the configuration file, 
    # then there's nothing to do.  Warn the users and exit.
    #
    if (!exists($config_hashref->{'Author'}) || 
        !defined($config_hashref->{'Author'}))
    {
        warn "Nothing to do -- no authors found in config file.\n";
        return;
    }

    # ----------------------------------------------------------------------
    # It's expected that users will have a list of authors, but if they 
    # only list a single author, then we need to convert the single hash
    # entry into an array of hashes for consistency in processing.
    #
    my @authors = (ref($config_hashref->{'Author'}) eq 'HASH') ?
        ($config_hashref->{'Author'}) : @{$config_hashref->{'Author'}};

    # ----------------------------------------------------------------------
    # Now perform additional sanity checks on the contents to make sure the 
    # configuration file is good.
    #
    my $liburl = $config_hashref->{'LibraryURL'};
    my $default_media_type = $config_hashref->{'MediaType'} // $DEFAULT_MEDIA;

    unless (config_ok($liburl, $default_media_type, \@authors))
    {
        warn "\nTo view processed config file, rerun with command line " .
             "option '-v'.\n";
        exit(2);
    }

    # ----------------------------------------------------------------------
    # Loop through list of authors and extract the entities (books, dvds,
    # ebooks, or whatever is specified in the config file) and list those
    # that were published this year.
    #
    process_webpage($liburl, $default_media_type, \@authors, $sort_option);

    return;
}

main();
