use strict;
use warnings;

package Net::ZXTM;

our $VERSION;

#ABSTRACT: Zeus Traffic Manager REST API

use LWP;
use JSON;
use IO::Socket::SSL qw(SSL_VERIFY_NONE);

use Data::Dumper;
use Config::IniFiles;

use Log::Log4perl qw(:easy);

use Carp;

sub configuration {
  my $config_file = "zxtm.conf";
  
  my @dirs = (".");
  push @dirs, "$ENV{HOME}/zxtm" if exists $ENV{HOME};
  push @dirs, ( "/etc/", "$FindBin::Bin/.." );
  
  foreach my $cfg_dir ( @dirs ) {
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
    my ( $class, $url, $username, $password ) = @_;

    my $self = bless {
        url        => $url,
        api        => $url,
        api_prefix => "",
    }, $class;

    my $ua = LWP::UserAgent->new(
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
    }
    else {
        die "Can't double-init!";
    }
}

sub get {
    my ( $self, $url ) = @_;

    return $self->{ua}->get($url);
}

sub call {
    my ( $self, $call ) = @_;

    my $url = $self->{api} . $call;

    my $resp = $self->get($url);

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

        if ( $resp->content ) {
            my $content_type = $resp->header('Content-type');

            my $json = {};

            if ( $content_type eq 'text/json' ) {
                eval { $json = from_json( $resp->content ); };
            }

            if ( exists $json->{error_id} ) {
                $error_id = $json->{error_id};
            }
            if ( exists $json->{error_text} ) {
                $error_text = $json->{error_text};
            }
        }
        warn "Failed to talk to ZXTM ($url): $error_id: \"$error_text\"";
        return [];
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
