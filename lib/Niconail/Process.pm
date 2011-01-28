# 
# ldd /Library/Perl/5.8.6/darwin-thread-multi-2level/auto/Imager/Imager.bundle
# -> freetype が必要。

package Niconail::Process;

use Any::Moose;

use Imager;
use Imager::Fill;
use Imager::DTP::Textbox::Horizontal;

use DateTime;
use DateTime::Format::W3CDTF;
use XML::Twig;

use AnyEvent::HTTP;
use LWP::UserAgent;

use utf8;

has 'config' => (
	is => 'rw',
	isa => 'HashRef',
);

has 'font_file_normal' => (
	is => 'rw',
	isa => 'Path::Class::File',
);

has 'font_file_bold' => (
	is => 'rw',
	isa => 'Path::Class::File',
);

has 'base_image' => (
	is => 'rw',
	isa => 'Path::Class::File',
);

has 'id' => (
	is => 'rw',
	isa => 'Str',
);

## internal

has 'first_retrieve' => (
	is => 'rw',
	isa => 'DateTime',
);

has 'title' => (
	is => 'rw',
	isa => 'Str',
);

has 'description' => (
	is => 'rw',
	isa => 'Str',
);

has 'comment' => (
	is => 'rw',
#	isa => 'ArrayRef[Str]',
	isa => 'Str',
);

has 'video_length' => (
	is => 'rw',
	isa => 'Str',
);

has 'view_counter' => (
	is => 'rw',
	isa => 'Int',
);

has 'comment_num' => (
	is => 'rw',
	isa => 'Int',
);

has 'mylist_counter' => (
	is => 'rw',
	isa => 'Int',
);

## core

has 'base' => (
	is => 'rw',
	isa => 'Imager',
	default => sub { Imager->new( xsize => 314, ysize => 178 ) },
);

has 'title_height' => (
	is => 'rw',
	isa => 'Num',
);

has 'description_height' => (
	is => 'rw',
	isa => 'Num',
);

has 'image_cv' => (
	is => 'rw',
	isa => 'AnyEvent::CondVar',
);

## box param

has 'normal_padding' => (
	is => 'rw',
	isa => 'Num',
	default => 4,
);

has 'title_base_y' => (
	is => 'rw',
	isa => 'Num',
	default => 30,
);

has 'title_width' => (
	is => 'rw',
	isa => 'Int',
	default => 194,
);

has 'comment_padding' => (
	is => 'rw',
	isa => 'Int',
	default => 6,    # px
);

has 'aa' => (
	is => 'rw',
	isa => 'Int',
	default => 1,
);

extends 'Class::ErrorHandler';

sub create_thumbnail {
	my $self = shift;
	
	# 背景を塗っておく
	$self->base->box( color => 'white', filled => 1 );
	$self->base->read( file => $self->base_image, bits => 8 );
	
	# image
	$self->set_image
		or return;
	
	# info
	$self->set_video_info
		or return;
	
	# first_retrieve
	$self->add_first_retrieve( $self->first_retrieve );
	
	# title
	$self->add_title;
	
	# description
	$self->add_description;
	
	# comment
	$self->add_comment;
	
	# video_length
	$self->add_video_length;
	
	# view_counter
	$self->add_view_counter;

	# comment_num
	$self->add_comment_num;

	# mylist_counter
	$self->add_mylist_counter;
	
	# reduce colors
	$self->base( $self->base->to_paletted( { make_colors => 'addi', translate => 'perturb' } ) );
	$self->base( $self->base->to_paletted( { max_colors => 8, translate => 'perturb' } ) );
	
	# remove alpha channel
	$self->base( $self->base->convert( preset => 'noalpha' ) );
	
	$self->image_cv->recv;
	
	my $content;
	if( not $self->config->{use_magick_quantize} ){
		$self->base->write( data => \$content, type => 'png' )
			or HTTP::Exception::500->throw;
	}
	else{
		require File::Temp;
		require Image::Magick;
		
		my ($fh, $filename) = File::Temp::tempfile( "tempXXXXXX", DIR => "/dev/shm", SUFFIX => "png", UNLINK => 0 );
		$self->base->write( fh => $fh, type => 'png' )
			or HTTP::Exception::500->throw;
		$fh->close;
		
		my $i = Image::Magick->new;
		$i->Read( $filename );
		$i->Quantize( color => 8 ); 
		$i->Write( $filename );
		
		open my $rfh, $filename
			or HTTP::Exception::500->throw;
		
		$content = do { local $/; <$rfh> };
		$rfh->close;
		
		unlink $filename;
	}
	
	return $content
}

sub set_image {
	my $self = shift;

	( my $video_n = $self->id ) =~ s/^[a-z]+//o;
	my $url = sprintf "http://tn-skr%d.smilevideo.jp/smile?i=%d", int( rand( 3 )  ) + 1, $video_n;
	
	$self->image_cv( AnyEvent->condvar );
	
	my $guard; $guard = http_get $url, timeout => 5, sub {
		my ($content, $header) = @_;
		undef $guard;
		
		if( ! $content ){
			$self->image_cv->send;
			return $self->error("FAILED_TO_RETRIEVE");
		}
		
		# load
		if( my $image = Imager->new( data => $content, type => 'jpeg' ) ){
			
			# scale (94x70)
			$image = $image->scale( xpixels => 94, ypixels => 70, type=>'max' );
			
			# crop
			if( $image->getwidth > 94 or $image->getheight > 70 ){
				$image = $image->crop( width => 94, height => 70 );
			}
			
			# paste
			$self->base->paste( src => $image, left => 10, top => 27 );
		}
		else{
			$self->image_cv->send;
			$self->error("FAILED_TO_RETRIEVE");
		}
		
		$self->image_cv->send;
	};
	
	return $self;
}

### add items:

sub add_first_retrieve {
	my $self = shift;

	my $str = sprintf "%02d/%02d/%02d %02d:%02d 投稿", map { $self->first_retrieve->$_() } qw(year month day hour minute);
	
	my $font = Imager::Font->new(
		$self->common_font_param,
		color => "#000000",
		size  => 10.8,
	) or die Imager->errstr;
	
	$self->base->string(
		font => $font,
		text => $str,
		x => 112,
		y => 22,
	);
}

sub add_title {
	my $self = shift;

	# 薄い色をバックに乗せる
	my $margin = 0.1;
	my $tb = $self->get_title_box( $self->title, "#DFE6EF" );
	$tb->draw( target => $self->base, x => 112 - $margin, y => $self->title_base_y - $margin );
	$tb->draw( target => $self->base, x => 112 + $margin, y => $self->title_base_y - $margin );
	$tb->draw( target => $self->base, x => 112 - $margin, y => $self->title_base_y + $margin );
	$tb->draw( target => $self->base, x => 112 + $margin, y => $self->title_base_y + $margin );

	# 濃い色を乗せる
	$tb = $self->get_title_box( $self->title, "#54789a" );
#	$tb = $self->get_title_box( $self->title, "#475B73" );
	$tb->draw( target => $self->base, x => 112, y => $self->title_base_y );
	
	# set height
	$self->title_height( $tb->getHeight );
	
	return $self;
}

sub add_description {
	my $self = shift;
	
	# URL などを削る
	$self->{description} =~ s{^s?https?:\/\/[-_.!~*'()a-zA-Z0-9;\/?:\@&=+\$,%#]+$}{[URL]};    # '
	$self->{description} =~ s{^[a-zA-Z0-9\-\_\.]+\@[a-zA-Z0-9\-\_\.]+$}{[MAIL]};
	
	my $tb = $self->get_description_box( $self->description );
	
	my $height = $self->title_base_y + $self->title_height + $self->normal_padding;
	
	$tb->draw( target => $self->base, x => 112, y => $height );

	# set height
	$self->description_height( $tb->getHeight );
	
	return $self;
}

sub add_comment {
	my $self = shift;

	my $tb = $self->get_comment_box( [ $self->comment ] );
	
	# comment
	my $height = $self->title_base_y
		+ $self->title_height + $self->normal_padding
		+ $self->description_height + $self->normal_padding
		+ $self->comment_padding;
	
	# 背景を適当に塗る
	my $base_x = 112;
	my $base_y =  $height - $self->comment_padding;
	my $base_x_max =  $base_x + $tb->getWidth + ( $self->comment_padding * 2 );
	my $base_y_max = $base_y + $tb->getHeight + ( $self->comment_padding * 2 );
	
	# 外側（内側を計算して、それに枠を付ける）
	$self->base->box(
		xmin =>  $base_x - 1,
		ymin => $base_y - 1,
		xmax => $base_x_max + 1,
		ymax =>  $base_y_max + 1,
		color => "#dddddd",
		filled => 1,
	);	
	
	# 内側
	$self->base->box(
		xmin =>  $base_x,
		ymin => $base_y,
		xmax => $base_x_max,
		ymax =>  $base_y_max,
		color => "#f3f3f3",
		filled => 1,
	);	
	
	$tb->draw( target => $self->base, x => 112 + $self->comment_padding, y => $height );

	return $self;
}

sub add_video_length {
	my $self = shift;

	my $str = sprintf "時間: %s", $self->video_length;
	my $tb = $self->get_video_length_box( $str );
	
	$tb->draw( target => $self->base, x => 11, y => 106 );
}

sub add_view_counter {
	my $self = shift;

	my $str = sprintf "再生: %s", $self->_format_count( $self->view_counter, 100 );

	my $tb = $self->get_view_counter_box( $str );
	
	$tb->draw( target => $self->base, x => 11, y => 106 + 14 );
}

sub add_comment_num {
	my $self = shift;

	my $str = sprintf "コメント: %s",$self->_format_count( $self->comment_num, 100 );
	my $tb = $self->get_comment_num_box( $str );
	
	$tb->draw( target => $self->base, x => 11, y => 106 + ( 14 * 2 ) );
}

sub add_mylist_counter {
	my $self = shift;

	my $str = sprintf "マイリスト: %s",$self->_format_count( $self->mylist_counter, 10 );
	my $tb = $self->get_mylist_counter_box( $str );
	
	$tb->draw( target => $self->base, x => 11, y => 106 + ( 14 * 3 ) );
}

### box:

sub common_font_param {
	my $self = shift;
	
	return (
		file => $self->font_file_normal,
		utf8 => 1,
		type => 'ft2',
		aa => $self->aa,
	);
}

sub common_textbox_param {
	my $self = shift;
	
	return (
		wspace => 0,       # set word distance (pixels)
		leading => 140,    # set line distance (percent)
		halign => 'left',  # set horizontal alignment
		valign => 'top',   # set vertical alignment
	);
}

sub get_title_box {
	my $self = shift;
	my ($str, $color) = @_;
	
#	my $color = Imager::Color->new( 84, 120, 154, 64 );    
	
	my $font = Imager::Font->new(
		$self->common_font_param,
		file => $self->font_file_bold,
		color => $color,
		size  => 13.2,
	) or die Imager->errstr;
	
	my %option = (
		$self->common_textbox_param,
		leading => 140,    # set line distance (percent)
		wrapWidth => $self->title_width,  # set text wrap width
#		wrapHeight => 80, # set text wrap height
	);
	
	my $n = 20;
	my $s;
	while(1){
		# fail-safe
		if( ++$n > 500 ){
			warn "reach infinit loop";
			last;
		}
		
		$s = substr( $str, 0, $n );
		
		my $tb = Imager::DTP::Textbox::Horizontal->new( %option,
			text => $s,     # set text
			font => $font,     # set font
		);
		
		# ３行になったら、１文字ずつ削って押し込める
		if( $tb->getHeight > 36 ){
			my $i = 0;
			while(1){
				$i++;
				
				$s = sprintf "%s..", substr $s, 0, ( length( $s ) - $i  );
				
				my $tb = Imager::DTP::Textbox::Horizontal->new( %option,
					text => $s,     # set text
					font => $font,     # set font
				);
				
				next if $tb->getHeight > 36;
				
				return $tb;
			}
		}
		else{
			if( $s eq $str ){
				return $tb;
			}
		}
	}
}

sub get_description_box {
	my $self = shift;
	my ($str) = @_;
	
	my $font = Imager::Font->new(
		$self->common_font_param,
		color => "#5c5c5c",
		size  => 10.5,
	) or die Imager->errstr;
	
	my %option = (
		$self->common_textbox_param,
		leading => 130,    # set line distance (percent)
		wrapWidth => $self->title_width,  # set text wrap width
#		wrapHeight => 80, # set text wrap height
	);
	
	my $n = 30;
	my $s;
	my $tb;
	while(1){
		# fail-safe
		if( ++$n > 100 ){
			warn "reach infinit loop";
			last;
		}
		
		$s = substr( $str, 0, $n );
		
		$tb = Imager::DTP::Textbox::Horizontal->new( %option,
			text => $s,     # set text
			font => $font,     # set font
		);
		
		if( length $s == length $str ){
			return $tb;
		}
		
		if( $tb->getHeight > 44 ){
			# ちょんぎる必要あり
			$s = sprintf "%s..", substr $s, 0, ( length( $s ) - 2 );
			
			return Imager::DTP::Textbox::Horizontal->new( %option,
				text => $s,     # set text
				font => $font,     # set font
			);
		}
	}
	
	# 想定内の長さだった
	return $tb;
}

sub get_comment_box {
	my $self = shift;
	my ($comment) = @_;
	
	my $str = join q{ }, @{ $comment};
	
	# 限界高さを計算する
	my $height_limit = 178 -
		( $self->title_base_y
		+ $self->title_height + $self->normal_padding
		+ $self->description_height + $self->normal_padding
		+ $self->comment_padding
		)
		- $self->comment_padding;

	my $font = Imager::Font->new(
		$self->common_font_param,
		color => "#000000",
		size  => 11,
	) or die Imager->errstr;
	
	my %option = (
		$self->common_textbox_param,
		leading => 130,    # set line distance (percent)
		wrapWidth => scalar( $self->title_width - ( $self->comment_padding * 2 ) ),
#		wrapHeight => 80, # set text wrap height
	);
	
	my $n = 30;
	my $s;
	my $tb;
	while(1){
		# fail-safe
		if( ++$n > 100 ){
			warn "reach infinit loop";
			last;
		}
		
		$s = substr( $str, 0, $n );
		
		$tb = Imager::DTP::Textbox::Horizontal->new( %option,
			text => $s,     # set text
			font => $font,     # set font
		);
		
		if( length $s == length $str ){
			return $tb;
		}
		
		if( $tb->getHeight > $height_limit ){
			# ちょんぎる必要あり
			$s = sprintf "%s..", substr $s, 0, ( length( $s ) - 2 );
			
			return Imager::DTP::Textbox::Horizontal->new( %option,
				text => $s,     # set text
				font => $font,     # set font
			);
		}
	}
	
	# 想定内の長さだった
	return $tb;
}

sub set_video_info {
	my $self = shift;
	
	my $info = {};
	
	my $info_url = sprintf "http://ext.nicovideo.jp/api/getthumbinfo/%s", $self->id;
	
	my $ua = LWP::UserAgent->new;
	$ua->timeout( 5 );
	$ua->env_proxy;
	my $res = $ua->get( $info_url  );
	
	if( $res->is_success ){
		my $handler = {};
		
		$handler->{'/nicovideo_thumb_response/thumb'} = sub {
			my ($tree, $elem) = @_;
			for my $item( $elem->children ){
				# get all
				my @key = qw(title description first_retrieve length view_counter comment_num mylist_counter last_res_body no_live_play);
				
				for my $key( @key ){
					if( $item->name eq $key ){
						$info->{$key} = &unescape_html( $item->trimmed_text );
					}
				}
			}
		};
		
		$handler->{'/nicovideo_thumb_response/error'} = sub {
			my ($tree, $elem) = @_;
			
			for my $item( $elem->children ){
				if( $item->name eq 'code' ){
					if( $item->trimmed_text eq 'DELETED' ){
						die $self->error("DELETED");
					}
					elsif( $item->trimmed_text eq 'NOT_FOUND' ){
						die $self->error("NOT_FOUND");
					}
					else{
						die $self->error("CANNOT_PLAY");
					}
				}
			}
		};
		
		# parse
		my $twig = XML::Twig->new( TwigHandlers => $handler );
		eval { $twig->parse( $res->decoded_content ); 1 }
			or return;
		
		if( defined $info->{title} and $info->{title} ne '' ){
			# first_retrieve
			my $f = DateTime::Format::W3CDTF->new;
			$info->{first_retrieve} = eval { $f->parse_datetime( $info->{first_retrieve} ) };
			
			my $tz = DateTime::TimeZone->new( name => 'Asia/Tokyo' );
			my $now = DateTime->now( time_zone => $tz );
		}
		else{
			return $self->error("CANNOT_PLAY");
		}
	}
	else{
		return $self->error("FAILED_TO_RETRIEVE");
	}
	
	$self->first_retrieve( $info->{first_retrieve} );
	$self->title( $info->{title} );
	$self->description( $info->{description} );
	$self->video_length( $info->{length} );
	$self->view_counter( $info->{view_counter} );
	$self->comment_num( $info->{comment_num} );
	$self->mylist_counter( $info->{mylist_counter} );

	$self->comment( $info->{last_res_body} );

	return $self;
}

sub get_video_length_box {
	my $self = shift;
	my ($str) = @_;
	
	my $font = Imager::Font->new(
		$self->common_font_param,
		color => "#000000",
		size  => 10.0,
	) or die Imager->errstr;
	
	return Imager::DTP::Textbox::Horizontal->new( $self->common_textbox_param,
		text => $str,     # set text
		font => $font,     # set font
	);
}

sub get_view_counter_box {
	my $self = shift;

	$self->get_video_length_box( @_ );
}

sub get_comment_num_box {
	my $self = shift;

	$self->get_video_length_box( @_ );
}

sub get_mylist_counter_box {
	my $self = shift;

	$self->get_video_length_box( @_ );
}

### utils:

sub _format_count {
	my $self = shift;
	my ($n, $max) = @_;
	$max //= 100;

	if( $n > 100 * 10000  ){
		return sprintf "%s万↑", &comma( int( $n  / 10_000 ) );
	}
	else{
		return sprintf "%s", &comma( int( $n ) );
	}
}

sub comma {
	local $_  = shift // "";
	1 while s/((?:\A|[^.0-9])[-+]?\d+)(\d{3})/$1,$2/s;
	return $_;
}

sub unescape_html {
	my $string = shift;
	$string=~ s[&(.*?);]{
		local $_ = $1;
		/^amp$/i        ? "&" :
		/^quot$/i       ? '"' :
		/^gt$/i         ? ">" :
		/^lt$/i         ? "<" :
#		/^#(\d+)$/ && $latin         ? chr($1) :
#		/^#x([0-9a-f]+)$/i && $latin ? chr(hex($1)) :
		$_
		}gex;
	return $string;
}

__PACKAGE__->meta->make_immutable;

use namespace::autoclean;

__END__

