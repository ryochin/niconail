# 

PROJECT = niconail
BASE = /project/$(PROJECT)

PERL = /usr/bin/perl -I$(BASE)/lib -I$(BASE)/extlib

install::
	$(NICE) $(PERL) install/installer.pl -q
	chmod 755 $(BASE)/service/run > /dev/null 2>&1

# EOF
