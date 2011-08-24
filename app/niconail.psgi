# 

use strict;
use lib qw(lib ../lib);
use HTTP::Exception;
use Plack::Request;
use Plack::Response;
use Plack::Builder;

use IO::File;
use Fcntl qw(:flock);use Path::Class qw(dir file);
use Cache::Memcached::Fast;
use HTTP::Date;
use Text::Xslate;
use YAML;

use Niconail::Process;

use utf8;
use Encode ();

my $config = YAML::LoadFile("/project/niconail/var/config.yml") or die $!;

my $cache_expire = 3 * 60 ** 2;    # 3 hrs
my $http_expire = int( $cache_expire / 2 );

my $var_dir = dir( $config->{project_base}, "var" );
my $font_file_normal = file( $var_dir, $config->{font_filename} );
my $font_file_bold = $font_file_normal;

my $app = sub {
	my $env = shift;
	my $req = Plack::Request->new( $env );
	
	( my $id =  $req->env->{PATH_INFO} ) =~ s{^/+}{}go;
	my $ignore_cache = 0;
	if( $id =~ s{\+$}{}o ){
		$ignore_cache = 1;
	}
	
	# トップページ
	if( $id !~ qr/^(sm|nm|so)[0-9]+$/o ){
		return process_index( $req );
	}
	
	my $key = sprintf "nn:%s", $id;
	my $memd = Cache::Memcached::Fast->new( { servers => [ $config->{memcached_server} ] } );
	
	# キャッシュにあるかどうか探す
	if( ! $ignore_cache and my $content = $memd->get( $key ) ){
		# あれば返す
		return prepare_response( $content );
	}
	
	# キャッシュになければ作成を試みる
	my $nico = Niconail::Process->new;
	$nico->req( $req );
	$nico->config( $config );
	$nico->base_image( file( $var_dir, "frame_base.png" ) );
	$nico->font_file_normal( $font_file_normal );
	$nico->font_file_bold( $font_file_bold );
	$nico->id( $id );
	
	# create
	my $content = $nico->create_thumbnail;
	
	my $failed = 0;
	if( defined $nico->errstr ){
		if( $nico->errstr eq 'FAILED_TO_RETRIEVE' ){
			$content = file( $var_dir, "frame_failed_to_retrieve.png" )->slurp or die $!;
			$failed = 1;
		}
		elsif( $nico->errstr eq 'NOT_FOUND' ){
			$content = file( $var_dir, "frame_not_found.png" )->slurp or die $!;
		}
		elsif( $nico->errstr eq 'DELETED' ){
			$content = file( $var_dir, "frame_deleted.png" )->slurp or die $!;
		}
		elsif( $nico->errstr eq 'CANNOT_PLAY' ){
			$content = file( $var_dir, "frame_cannot_play.png" )->slurp or die $!;
		}
	}
	
	# メモリに入れる
	$memd->set( $key, $content, $failed ? 10 * 60 : $cache_expire );
	
	# 返す
	return prepare_response( $content );
};

sub process_index {
	my $req = shift;

	my $tx = Text::Xslate->new(
		syntax => 'TTerse',
		path => [ $var_dir ],
		cache => 1,
	);
	
	my $stash = {};
	$stash->{config} = $config;
	
	my $id;
	if( defined( $id =  $req->param('id') ) ){
		$id =~ s{^.*((sm|nm|so)[0-9]+?)$}{$1}o;
	}
	else{
		$id = "sm9";
	}
	
	$stash->{id} = $id;
	
	my $res = Plack::Response->new( 200 );
	$res->content_type("text/html; charset=UTF-8");
	$res->body( Encode::encode_utf8( $tx->render("index.html", $stash ) ) );
	
	return $res->finalize;
}

sub prepare_response {
	my $content = shift;
	
	my $res = Plack::Response->new( 200 );
	$res->content_type("image/png");
	$res->headers( [ "Cache-Control" => "private" ] );
	$res->headers( [ "Expires" => HTTP::Date::time2str( time() + $http_expire ) ] );
	$res->body( $content );
	
	return $res->finalize;
}

my $log_dir = dir( $config->{project_base}, "logs" );
my $log_file = file( $log_dir, 'backend.log' );
my $logger = sub {
	my $fh = IO::File->new( $log_file, O_CREAT|O_WRONLY|O_APPEND ) or die $!;
	flock $fh, LOCK_EX;    # get lock for infinity
	seek $fh, 0, LOCK_EX;
	$fh->print(@_);
	flock $fh, LOCK_UN;    # release lock
	$fh->close;
};

use Log::Dispatch::Config;
Log::Dispatch::Config->configure( file( $config->{project_base}, "var", "log_web.conf" )->stringify );

builder {
	enable 'AccessLog', format => 'combined', logger => $logger;
	enable 'ContentLength';
	enable 'HTTPExceptions';
	enable 'Head';
	enable 'Runtime';
	enable 'LogDispatch', logger => Log::Dispatch::Config->instance;
	enable_if { $_[0]->{REMOTE_ADDR} eq '127.0.0.1' }
		'ReverseProxy';
	enable 'Static', path => qw{^/(?:favicon\.(ico|png)|robots\.txt)$}, root => dir( $config->{project_base}, "htdocs" );
	$app;
};
 
__END__