use strict;
use warnings;

package Net::ZXTM;

our $VERSION;

#ABSTRACT: Zeus Traffic Manager REST API

use LWP::UserAgent::Determined;

use JSON;
use IO::Socket::SSL qw(SSL_VERIFY_NONE);

use Data::Dumper;
use Config::IniFiles;
use Cache::FileCache;

use Log::Log4perl qw(:easy);

use Carp;

#XXX: Inject, CHI-style
sub Cache::BaseCache::compute {
    my ( $self, $key, $expiry, $sub ) = @_;

    my $val = $self->get($key);

    if ( defined $val ) {
        return $val;
    }

    $val = $sub->();
    $self->set( $key, $val, $expiry );
    return $val;
}

sub configuration {
    my $config_file = "zxtm.conf";

    my @dirs = (".");
    push @dirs, "$ENV{HOME}/zxtm" if exists $ENV{HOME};
    push @dirs, ( "/etc/", "$FindBin::Bin/.." );

    foreach my $cfg_dir (@dirs) {
        if ( -f "$cfg_dir/$config_file" ) {
            $config_file = "$cfg_dir/$config_file";
            carp "Using config from $config_file";
            last;
        }
    }

    my $cfg = Config::IniFiles->new(
        -file     => $config_file,
        -fallback => "global",
        -default  => "global",
    ) || die "Can't read zxtm.conf";

    return $cfg;
}

sub new {
    my ( $class, $url, $username, $password, $cfg ) = @_;

    my $self = bless {
        url        => $url,
        api        => $url,
        api_prefix => "",
        config     => $cfg,
    }, $class;

    my $ua = LWP::UserAgent::Determined->new(
        timeout    => 30,
        keep_alive => 8,
    );

    # Set SSL Options
    if ( $ua->can('ssl_opts') ) {
        $ua->ssl_opts(
            verify_hostname => undef,
            SSL_verify_mode => SSL_VERIFY_NONE,
        );
    }

    my $uri = URI->new($url);

    my $host = $uri->host;
    my $port = $uri->port;

    $ua->credentials(
        "$host:$port", "Stingray REST API", $username, $password,

    );

    $self->{ua} = $ua;

    $self->init();

    return $self;
}

sub init {
    my $self = shift;

    if ( not defined $self->{_init} ) {
        $self->{_init} = 1;

        my $apis     = $self->call("/api/tm/");
        my $api_ver  = 0;
        my $api_href = "";
        foreach my $api (@$apis) {
            if ( $api->{name} >= $api_ver ) {
                $api_ver = $api->{name};
                ( $api_href = $api->{href} ) =~ s[/+$][];
            }
        }
        my $url = URI->new( $self->{url} . $api_href );
        $self->{api}        = $url->canonical;
        $self->{api_prefix} = $url->path;

        my $cfg   = $self->{config};
        my $cache = Cache::FileCache->new(
            {
                cache_root => $cfg->val( 'global', 'cache', 'cache' ),
                namespace  => 'Net::ZXTM',
                default_expires_in =>
                  $cfg->val( 'global', 'cache_expiry', '60m' ),
            }
        );
        $self->{cache} = $cache;

    }
    else {
        die "Can't double-init!";
    }
}

sub get {
    my ( $self, $url ) = @_;

    return $self->{ua}->get($url);
}

# LWP::UserAgent->put is relatively new...
# Monkey-patch it in if it isn't there yet.
unless (LWP::UserAgent->can('put')) {
  *LWP::UserAgent::put = sub {
    require HTTP::Request::Common;
    my($self, @parameters) = @_;
    my @suff = $self->_process_colonic_headers(\@parameters, (ref($parameters[1]) ? 2 : 1));
    return $self->request( HTTP::Request::Common::PUT( @parameters ), @suff );
  };
}

sub put {
    my ( $self, $url, $data ) = @_;

    my $json = to_json($data);
    return $self->{ua}->put(
        $url,
        Content        => $json,
        'Content-type' => 'application/json'
    );
}

sub cache { shift->{cache} }

sub cached_call {
    my ( $self, $api ) = @_;

    my $cache = $self->cache;

    my $key = $self->{url} . $api;

    return $cache->compute( $key, undef, sub { $self->call($api) } );
}

#XXX: This needs to do a cache refresh
sub call_refresh {
    my ( $self, $api) = @_;
   
    my $cache = $self->cache;
    my $key = $self->{url} . $api;
    
    $cache->remove($key);

    return $self->cached_call( $api );
}

sub alter {
    my ( $self, $call, $payload ) = @_;

    return $self->call( $call, $payload );
}

sub call {
    my ( $self, $call, $payload ) = @_;

    my $url = $self->{api} . $call;
    
    my $resp;
    if ($payload) {
        $resp = $self->put( $url, $payload );
    }
    else {
        $resp = $self->get($url);
    }

    if ( $resp->is_success ) {
        my $json = from_json( $resp->content );
        if ( exists $json->{children} ) {
            $json = $json->{children};

            foreach my $c (@$json) {
                if ( exists $c->{href} ) {
                    $c->{href} =~ s/^$self->{api_prefix}//;
                }
            }

        }
        return $json;
    }
    else {
        my $error_id   = "unknown";
        my $error_text = $resp->status_line;
        my $error_info = "";

        if ( $resp->content ) {
            my $content_type = $resp->header('Content-type');

            my $json = {};

            if (   $content_type eq 'application/json'
                or $content_type eq 'text/json' )
            {
                eval { $json = from_json( $resp->content ); };
            }

            if ( exists $json->{error_id} ) {
                $error_id = $json->{error_id};
            }
            if ( exists $json->{error_text} ) {
                $error_text = $json->{error_text};
            }

            #if ( exists $json->{error_info} ) {
            #    $error_info = Dumper($json->{error_info});
            #}
        }

        warn
"Failed to talk to ZXTM ($url): $error_id: \"$error_text\" $error_info";
        print Dumper($resp);
        return [];
    }
}

use Socket;

# returns the hostname for an ip, undef if passed a hostname
# XXX: Doesn't really belong here, doesn't it?
sub reverse_ip {
    my ( $self, $ip ) = @_;

    my $cache = $self->cache;

    my $reverse = $cache->compute( "reverse_ip($ip)", undef,
        sub { gethostbyaddr( inet_aton($ip), AF_INET ) || "" } );

    if ( defined $reverse ) {

# Return undef is reverse returned the same thing, most likely called with a hostname...
        return $reverse eq $ip ? "" : $reverse;
    }
    else {
        return "";
    }
}

=head2 version

prints current version to STDERR

=cut

sub version {
    return $VERSION || "git";
}

1;

=head1 SYNOPSIS

Zeus Traffic Manager REST API

=head1 METHODS

=head2 new

=head2 version

This method returns a reason.
