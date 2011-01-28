#!/usr/bin/perl --
# 

use strict;
use 5.010;
use Getopt::Std;
use IO::File;
use File::Basename qw(dirname);
use Path::Class qw(dir file);
use CPAN;

Getopt::Std::getopts 'fc:y' => my $opt = {};
# -f: force exec
# -c: config file
# -y: all yes

my $prereq_file = $opt->{c} || file( dirname( $0 ), "./prereq-modules.txt" )->stringify;

$< == 0 or $opt->{f}
	or die "You need have a root privilege to exectute me !";

my $interactive = 0;
if( not defined $opt->{y} ){
	eval "use IO::Prompt";
	if( $@ ){
		printf STDERR "! there is no IO::Prompt, so interactive mode disabled.";
	}
	else{
		$interactive = 1;
	}
}

local $SIG{INT} = $SIG{HUP} = sub {
	printf STDERR "interrupt call detected.\n";
	exit 1;
};

# mod
my @module = &read_prereq( $prereq_file );
printf STDERR "* total %d modules will be installed, go ahead. \n", (scalar @module) / 2;

LOOP:
while( my ($module, $ver) = splice @module, 0, 2 ){
	if($ver){
		printf STDERR "===> installing %s (>%.2f) .. \n", $module, $ver;
	}
	else{
		printf STDERR "===> installing %s .. \n", $module;
	}
	eval sprintf "use %s %s", $module, $ver;
	if( $@ ){
		if( $interactive ){
			while( IO::Prompt::prompt( sprintf( "Do you want to install %s ? [y/n] ", $module ) ) ){
				if( /^ye*s*$/io ){
					&install( $module );
				}
				next LOOP;
			}
		}
		else{
			&install( $module );
		}
	}
	else{
		printf STDERR "installed, skip.\n";
	}
}
exit 0;

sub install {
	my $module = shift or return;
	CPAN::install $module;
}

sub read_prereq {
	my $file = shift or return;

	my $fh = IO::File->new( $file ) or die $!;
	my @modules = map { chomp; my($mod, $ver) = split /[\s\t]+/; ($mod => ( $ver =~ /^[\d\.]+$/o ? $ver : 0 ) ) }
		grep { /^\s*?\w+/ } $fh->getlines;
	return @modules;
}

__END__
