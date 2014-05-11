# ==========================================================================
# Unit tests for latest_books.pl
# ==========================================================================
use strict;
use warnings;

use Test::More;
use Test::Output;

my $SCRIPT = 'bin/latest_books.pl';

# ==========================================================================
# Test of command line options.
# ==========================================================================
stderr_like { qx{$SCRIPT -c} }  qr/Usage/, 
    'Test -c option with missing config file name';
stderr_like { qx{$SCRIPT -h} }  qr/Usage/, 
    'Test -h option';
stderr_like { qx{$SCRIPT -x} }  qr/Usage/, 
    'Test an invalid option';
like(qx{$SCRIPT -v -c t/default.conf}, qr/config/, 
    'Test -v command line option and good -c');
unlike(qx{$SCRIPT -sc t/bookmedia.conf}, qr/electronic/, 
    'Test -s command line option and specific media type');
like(qx{$SCRIPT -c t/bookmedia.conf}, qr/electronic/, 
    'Test without -s command line option and specific media type');

# ==========================================================================
# Test for errors related to the config file.
# ==========================================================================
stderr_like { qx{$SCRIPT -c t/missing.conf} }  qr/does not exist/, 
    'Test missing config file';
stderr_like { qx{$SCRIPT -c t/noauthors.conf} }  qr/no authors/, 
    'Test config file with no authors';
stderr_like { qx{$SCRIPT -c t/noliburl.conf} }  
    qr/URL missing/, 'Test config file with missing library URL';
stderr_like { qx{$SCRIPT -c t/nofirstname.conf} }  
    qr/first name/, 'Test config file with missing first name of author';
stderr_like { qx{$SCRIPT -c t/nolastname.conf} }  
    qr/last name/, 'Test config file with missing last name of author';
stderr_like { qx{$SCRIPT -c t/badmedia.conf} }  
    qr/MediaType/, 'Test config file with bad media type';
stderr_like { qx{$SCRIPT -c t/authorbadmedia.conf} }  
    qr/MediaType/, 'Test config file with bad media type for author';
stderr_like { qx{$SCRIPT -c t/badauthor.conf} }  
    qr/Manual search required/, 
    'Test config file with name of non-existent author';
stderr_like { qx{$SCRIPT -c t/badurl.conf} }  
    qr/Bad hostname/, 'Test config file with bad url';
stderr_like { qx{$SCRIPT -c t/noliburl.conf} }  
    qr/Library URL missing/, 'Test config file with no url';
stderr_like { qx{$SCRIPT -c t/untestedurl.conf} }  
    qr/ipac20\/ipac.jsp/, 'Test config file with non-ipac20 url';

like(qx{$SCRIPT -c t/nodefaultmedia.conf}, qr/Beaton/, 
    'Test use of default media type');

# ==========================================================================
# Test that configuration file options are applied.
# ==========================================================================
like(qx{$SCRIPT -c t/noignore.conf}, qr/Death/, 
    'Test that title is found -- verifies next two tests are valid');
unlike(qx{$SCRIPT -c t/ignoretitles.conf}, qr/Death/, 
    'Test ignore requests in config file');
unlike(qx{$SCRIPT -c t/ignoretitle.conf}, qr/Death/, 
    'Test ignore request (singular) in config file');

# ==========================================================================
# Other tests.
# ==========================================================================
like(qx{$SCRIPT -c t/relativeurl.conf}, qr/Death/, 
    'Test relative LibraryURL');

# ==========================================================================
# Done
# ==========================================================================
done_testing();
