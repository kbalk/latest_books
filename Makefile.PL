use ExtUtils::MakeMaker 6.96;

WriteMakefile(
    NAME          => 'latest_books',
    VERSION       => '0.01',
    EXE_FILES     => [ 'bin/latest_books.pl' ],
    PREREQ_PM     => {
                        'URI'             => 0,
                        'Web::Scraper'    => 0,
                        'Config::General' => 0,
                        'Getopt::Std'     => 0,               
                        'POSIX'           => 0,
                        'Try::Tiny'       => 0,
                        'File::Spec'      => 0,
                        'File::Basename'  => 0,
                        'Data::Dumper'    => 0,
                        'Test::More'      => 0,
                        'Test::Output'    => 0,
                      },

    # ----------------------------------------------------------------------
    # The following is overkill for the installation of one script and one 
    # config file that will most likely be installed in a user's home 
    # directory for personal use.
    # 
    NO_META       => 1,
    NO_MYMETA     => 1,
    MAN3PODS      => {},
    NO_PERLLOCAL  => 1,
    NO_PACKLIST   => 1,
);

# --------------------------------------------------------------------------
# Add a target for the configuration file used by latest_books.pl and make
# sure that target is installed.
#
sub MY::postamble {
        return << 'END_MAKEFILE';
pure_all :: $(INST_SCRIPT)/latest_books.conf
	$(NOECHO) $(NOOP)

realclean ::
	$(RM_F) $(INST_SCRIPT)/latest_books.conf 

install :: $(INST_SCRIPT)/latest_books.conf

$(INST_SCRIPT)/latest_books.conf : bin/latest_books.conf $(FIRST_MAKEFILE) $(INST_SCRIPT)$(DFSEP).exists $(INST_BIN)$(DFSEP).exists
	$(NOECHO) $(RM_F) $(INST_SCRIPT)/latest_books.conf
	$(CP) bin/latest_books.conf $(INST_SCRIPT)/latest_books.conf
	-$(NOECHO) $(CHMOD) $(PERM_RW) $(INST_SCRIPT)/latest_books.conf

END_MAKEFILE
}
