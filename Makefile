# 

PROJECT = niconail
BASE = /project/$(PROJECT)

NICE = /bin/nice -10
PERL = /usr/bin/perl -I$(BASE)/lib -I$(BASE)/extlib

install::
	$(NICE) $(PERL) install/installer.pl -q
	chmod 755 $(BASE)/service/run > /dev/null 2>&1

# EOF
