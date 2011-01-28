#!/usr/bin/perl --

use strict;
use lib qw(lib);
use Path::Class qw(file);
use YAML;

use Niconail::Process;

use utf8;

my $id = shift @ARGV // "sm9";

my $config = YAML::LoadFile("./var/config.yml.dist") or die $!;

my $nico = Niconail::Process->new;
$nico->config( $config );
$nico->base_image( file("./var/frame_base.png") );
$nico->font_file_normal( file("./var/ipaexg.ttf") );
$nico->font_file_bold( file("./var/ipaexg.ttf") );
#$nico->font_file_normal( file("./HiraKakuPro-W3.ttf") );
#$nico->font_file_bold( file("./HiraKakuPro-W6.ttf") );
$nico->id( $id );

my $content = $nico->create_thumbnail;
if( defined $nico->errstr ){
	die $nico->errstr;
}
else{
	my $fh = file("./result.png")->openw or die $!;
	$fh->write( $content );
	$fh->close;
}

__END__

