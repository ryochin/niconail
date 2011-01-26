#!/usr/bin/perl --
# 

use 5.008;
use strict;
use warnings;
use Getopt::Std;
use FindBin;
use File::Basename ();
use File::Path ();
use File::Copy ();
use File::Compare ();
use Path::Class qw(dir file);
use YAML::Syck;
use Term::ANSIColor;

umask 002;

Getopt::Std::getopts 't:nuqhr:' => my $opt = {};
# -t: target
# -n: dry run
# -u: uninstall
# -q: quiet
# -h: help
# -r: regex

my $recipe_dir = '.';
my $recipe_file = file( $FindBin::Bin => "recipe.yml" );
my $default_recipe = "base";

my $config = YAML::Syck::LoadFile( $recipe_file ) or die "cannot load $recipe_file.";

defined $opt->{h}
	and &HELP_MESSAGE;

my $debug = 1 if not defined $opt->{q};

my ($copied, $skipped, $failed, $deleted) = (0, 0, 0, 0);
if( defined $opt->{t} ){
	# one target
	if( defined $config->{ $opt->{t} } ){
		&main( $config->{ $opt->{t} } );
	}
	elsif( $opt->{t} eq 'all' ){
		# all target
		&main( keys %{ $config } );
	}
	else{
		warn "no such target.";
		&HELP_MESSAGE;
	}
}
else{
	# main one target
	&main( $config->{ $default_recipe } );
}

sub main {
	if( defined $opt->{u} ){
		&uninstall( @_ );
	}
	else{
		defined $opt->{n}
			and die "dry run mode is acceptable only for uninstall.";
		&install( @_ );
	}
}

sub install {
	my @file = &read_file(@_);

	while( my ($from, $to) = splice @file, 0, 2 ){
		if( defined $opt->{r} and $from !~ $opt->{r} ){
			next;
		}

		if( $to =~ m|/$|o ){
			# dir
			&make_dir( $to );
		}
		elsif( $from =~ m|^(sym)*link:|o ){
			# symlink
			$from =~ s{^(sym)*link:}{}o;
			&link_file( $from => $to );
		}
		else{
			# file
			&install_file( $from => $to );
		}
	}

	if( $debug ){
		if( $failed ){
			printf "===> total ";
			printf "%s%d copied%s, ", color('blue'),  $copied, color('reset');
			printf "%s%d skipped%s, ", color('green'),  $skipped, color('reset');
			printf "%s%d failed%s.\n", color('red'),  $failed, color('reset');
		}
		else{
			printf "===> total ";
			printf "%s%d copied%s, ", color('blue'),  $copied, color('reset');
			printf "%s%d skipped%s.\n", color('green'),  $skipped, color('reset');
		}
	}
}

sub uninstall {
	my @file = &read_file(@_);

	while( my ($from, $to) = splice @file, 0, 2 ){
		&uninstall_file( $from => $to );
	}

	printf "===> total %d deleted, %d failed. \n", $deleted, $failed if $debug;
}

sub read_file {
	my @project = @_;

	my @all_file;
	for my $project( @project ){
		my @file;
		for my $recipe( @{ $project->{recipe} } ){
			my $file_name = sprintf "%s.txt", $recipe;
			my $file = file( $FindBin::Bin, $recipe_dir, $file_name );
			
			my $fh = $file->openr or die "cannot read file '$file' !";
			while( defined( my $line = $fh->getline ) ){
				chomp $line;
				next if $line !~ /^\s*?\w+/o;
				
				my ($from, $to) = split /[\s\t]+/o, $line;
				
				$to ||= $from;
				$to = file( $project->{base} => $to )->stringify
					if $to !~ m|^/|o;
				
				push @all_file, $from, $to;
			}
		}
	}

	return @all_file;
}

sub install_file {
	my ($from, $to) = @_;

	# dir
	my $dir = File::Basename::dirname $to;
	unless( -d $dir ){
		printf "=> mkdir %s .. ", $dir if $debug;
		unless( eval { File::Path::mkpath $dir } ){
			print " ($!)" if $debug;
			$failed++;
		}
		print "\n" if $debug;
	}

	printf "=> copying %s -> %s ", $from, $to if $debug;

	# main
	if( ! -e $from ){
		# from file not found.
		printf "%s [file not found !]%s", color('red'), color('reset') if $debug;
		$failed++;
	}
	elsif( File::Compare::compare($from, $to) == 0 ){
		# skip
		printf "%s[skip]%s", color('green'), color('reset') if $debug;
		$skipped++;
	}
	else{
		# copy
		if( File::Copy::copy($from, $to) ){
			$copied++;
		}
		else{
			printf "%s[$!]%s", color('red'), color('reset') if $debug;
			$failed++;
		}
	}

	print "\n" if $debug;
}

sub link_file {
	my ($from, $to) = @_;

	# dir
	my $dir = File::Basename::dirname $to;
	unless( -d $dir ){
		printf "=> mkdir %s .. ", $dir if $debug;
		unless( eval { File::Path::mkpath $dir } ){
			print " ($!)" if $debug;
		}
		print "\n" if $debug;
	}

	printf "=> linking %s -> %s ", $from, $to if $debug;

	# remove old link
	if( -l $to ){
		unlink $to;
	}

	# main
	if( eval { symlink($from, $to); 1 } ){
		$copied++;
	}
	else{
		printf "%s[$!]%s", color('red'), color('reset') if $debug;
		$failed++;
	}

	print "\n" if $debug;
}

sub uninstall_file {
	my ($from, $to) = @_;

	# skip directory
	if( $to =~ m|/$|o ){
		return;
	}

	printf "=> deleting %s", $to if $debug;

	if( unlink $to ){
		$deleted++;
	}
	else{
		print " ($!)" if $debug;
		$failed++;
	}

	print "\n" if $debug;
}

sub make_dir {
	my $dir = shift;

	unless( -d $dir ){
		printf "=> mkdir %s .. ", $dir if $debug;
		unless( eval { File::Path::mkpath $dir } ){
			print " ($!)" if $debug;
		}
		print "\n" if $debug;
	}
}

sub HELP_MESSAGE {
	my $program = scalar File::Basename::basename $0;
	my $target = join " ", keys %{ $config };
	print STDERR <<"USAGE";
usage: $program [-hqun] [-r <regex>] [-t <target>]
        target: $target
USAGE
	;
	exit 0;
}

__END__
