use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Business::OnlinePayment::SurePay',
    'VERSION_FROM'	=> 'SurePay.pm', # finds $VERSION
    'PREREQ_PM'		=> { 'Net::SSLeay' => 0,
                             'Business::OnlinePayment' => 0,
			   }, 
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'SurePay.pm', # retrieve abstract from module
       AUTHOR     => 'AKHOBOV <AKHOBOV@cpan.org>') : ()),
);
