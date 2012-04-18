package App::htmlcat;
use strict;
use warnings;
use 5.008_001;
use AnyEvent::Handle;
use HTML::FromANSI::Tiny;
use HTML::Entities;
use Data::Section::Simple qw(get_data_section);
use IO::Socket::INET;
use Plack::Runner;
use Encode;

our $VERSION = '0.01';

sub new {
    my ($class, @args) = @_;

    my $self = bless {
        args    => \@args,
        clients => {},
        ansi    => HTML::FromANSI::Tiny->new(
            auto_reverse  => 1,
            no_plain_tags => 1,
            html_encode   => sub { encode_entities($_[0], q("&<>)) },
        ),
    }, $class;

    $self->{in} = AnyEvent::Handle->new(
        fh => \*STDIN,
        on_eof => sub {
            my ($handle) = @_;
            exit 0;
        },
        on_error => sub {
            my ($handle, $fatal, $message) = @_;
            warn "stdin: $message\n";
            $self->_broadcast($_[0]{rbuf});
            exit 1;
        }
    );

    return $self;
}

sub _on_read_cb {
    my $self = shift;

    return sub {
        my ($handle) = @_;
        $self->_broadcast($handle->rbuf);
        $handle->rbuf = '';
    };
}

sub _broadcast {
    my ($self, $data) = @_;

    open my $fh, '<', \$data;
    while (defined (my $line = <$fh>)) {
        $line = decode_utf8 $line;
        foreach my $client (values %{ $self->{clients} }){ 
            $self->_push_line($client->{handle}, $line);
        }
    }
}

sub _push_line {
    my ($self, $handle, $line) = @_;
    $handle->push_write("data:" . Encode::encode("utf-8", scalar $self->{ansi}->html($line) ) );
    $handle->push_write("\n");
}

sub as_psgi {
    my $self = shift;

    return sub {
        my $env = shift;

        $env->{'psgi.streaming'} or die 'psgi.streaming not supported';

        if ($env->{PATH_INFO} eq '/stream') {
            return sub {
                my $respond = shift;

                my $remote_addr = $env->{REMOTE_ADDR};

                my $writer = $respond->([
                    200, [
                        'Content-Type' => 'text/event-stream; charset=utf-8',
                        'Cache-Control' => 'no-cache'
                    ]
                ]);

                my $io = $env->{'psgix.io'};
                my $handle = AnyEvent::Handle->new(
                    fh => $io,
                    on_error => sub {
                        my ($handle, $fatal, $message) = @_;
                        warn "client [$remote_addr]: $message\n";
                        delete $self->{clients}->{ 0+$io };
                        if (keys %{$self->{clients}} == 0) {
                            $self->{in}->on_read();
                        }
                    }
                );

                $self->{clients}->{ 0+$io } = {
                    handle => $handle,
                    writer => $writer, # keep reference
                };
                $self->{in}->on_read($self->_on_read_cb);
            };
        } elsif ($env->{PATH_INFO} eq '/css') {
            return [ 200, [ 'Content-Type' => 'text/css' ], [ $self->{ansi}->css ] ];
        } elsif ($env->{PATH_INFO} eq '/js') {
            return [ 200, [ 'Content-Type' => 'text/javascript' ], [ get_data_section('js') ] ];
        } elsif ($env->{PATH_INFO} eq '/') {
            return [ 200, [ 'Content-Type' => 'text/html; charset=utf-8' ], [ get_data_section('html') ] ];
        } else {
            return [ 404, [], [] ];
        }
    };
}

sub run {
    my $self = shift;
    my $runner = Plack::Runner->new(app => $self->as_psgi);
    $runner->parse_options(
        '--env' => 'production',
        '--port' => _empty_port(),
        @{ $self->{args} }
    );

    if (my $exec = { @{$runner->{options}} }->{exec}) {
        push @{ $runner->{options} }, server_ready => sub {
            my ($args) = @_;
            my $host  = $args->{host} || 'localhost';
            my $proto = $args->{proto} || 'http';
            system "$exec $proto://$host:$args->{port}/";
        };
    } else {
        push @{ $runner->{options} }, server_ready => sub {
            my ($args) = @_;
            my $host  = $args->{host} || 'localhost';
            my $proto = $args->{proto} || 'http';
            print STDERR "$0: $proto://$host:$args->{port}/\n";
        };
    }

    $runner->run;
}

# from Test::TCP
sub _empty_port {
    my $port = $ENV{HTTPCAT_PORT} || 45192 + int(rand() * 1000);

    while ($port++ < 60000) {
        my $remote = IO::Socket::INET->new(
            Proto    => 'tcp',
            PeerAddr => '127.0.0.1',
            PeerPort => $port,
        );

        if ($remote) {
            close $remote;
        } else {
            return $port;
        }
    }

    die 'Could not find empty port';
}
__DATA__

@@ html
<!DOCTYPE html>
<html>
<head>
<title>htmlcat</title>
<link rel="stylesheet" type="text/css" href="/css">
<script type="text/javascript" src="/js"></script>
<script type="text/javascript">
window.onload = function () {
    var es = new EventSource("/stream");
    es.onmessage = function(event) {
        var data = {};
        data.html = event.data;
        if (!data.html) {
            return;
        }

        if (window.scrollY + document.documentElement.clientHeight >= document.documentElement.scrollHeight) {
            var scrollToBottom = true;
        }

        var div = document.createElement('div');
        div.innerHTML = data.html + "\n";

        var out = document.getElementById('out');
        while (div.firstChild) {
            out.appendChild(div.firstChild);
        }

        document.title = data.html.replace(/<.*?>/g, '') + ' - htmlcat';

        if (scrollToBottom) {
            window.scrollTo(0, document.body.scrollHeight);
        }
    };
};
</script>
</head>
<body>
<pre id="out"></pre>
</body>
</html>

@@ js
// TODO: for IE?  https://github.com/Yaffle/EventSource 

__END__

=head1 NAME

App::htmlcat - stdin to your browser

=head1 METHODS

=over 4

=item my $htmlcat = App::htmlcat->new(@ARGV)

Creates an instance.

As of I<@ARGV>, currently only C<--exec> option is handled
by C<htmlcat>, all others are sent to L<Plack::Runner>.

=item $htmlcat->as_psgi

Returns the htmlcat PSGI app.

=item $htmlcat->run

Does plackup internally and runs htmlcat.

=item empty_port

=back

=head1 AUTHOR

motemen E<lt>motemen@gmail.comE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
