#!/usr/bin/perl --

use strict;
use lib qw(lib);
use Niconail::Process;

use utf8;

my $id = shift @ARGV // "sm9";

my $nico = Niconail::Process->new;
$nico->base_image("./base.png");
$nico->font_file_normal("./ipaexg.ttf");
$nico->font_file_bold("./ipaexg.ttf");
#$nico->font_file_normal("./HiraKakuPro-W3.ttf");
#$nico->font_file_bold("./HiraKakuPro-W6.ttf");
$nico->id( $id );
my $image = $nico->create_thumbnail;
if( defined $nico->errstr ){
	warn $nico->errstr;
	if( $nico->errstr eq 'FAILED_TO_RETRIEVE' ){
		
	}
	elsif( $nico->errstr eq 'NOT_FOUND' ){
	
	}
	elsif( $nico->errstr eq 'DELETED' ){
	
	}
	elsif( $nico->errstr eq 'CANNOT_PLAY' ){
	
	}
}
else{
	$image->write( file => 'result.png' )
		or die $image->errstr;
}


__END__

