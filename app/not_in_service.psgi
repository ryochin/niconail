# 

use strict;
use Path::Class qw(file);

my $image_file = file("/web/niconail/var/frame_not_in_service.png");
my $html_file = file("/web/niconail/var/index.html");

my $app = sub {
	my $env = shift;
	
	if( $env->{PATH_INFO} =~ /\d$/o ){
		return [ 200,
			[ 'Content−Type' => 'image/png' ],
			[ $image_file->slurp ]
		];
	}
	else{
		return [ 200,
			[ 'Content−Type' => 'text/html' ],
			[ $html_file->slurp ]
		];
	}
};

__END__