# $Id: Makefile.PL,v 1.3 2003/11/16 17:36:15 mjb47 Exp $
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'DBIx::XMLServer',
    'VERSION_FROM'	=> 'XMLServer.pm', # finds $VERSION
    'PREREQ_PM'		=> { XML::LibXML => 1.54,
                             XML::LibXSLT => 1.53,
			     Parse::RecDescent => 1.90,
                           }, # e.g., Module::Name => 1.1
    'PL_FILES'          => { 
       'BuildParser.PL' => '$(INST_LIB)/DBIx/XMLServer/XPathParser.pm',
       'AskDatabase.PL' => 't/dbname'
    },
    clean => { FILES => 't/dbname' },
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'XMLServer.pm', # retrieve abstract from module
       AUTHOR     => 'Martin Bright <martin@boojum.org.uk>') : ()),
);
