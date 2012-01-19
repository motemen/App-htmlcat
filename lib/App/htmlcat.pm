package App::htmlcat;
use strict;
use warnings;
use AnyEvent::Handle;
use HTML::FromANSI::Tiny;
use Data::Section::Simple qw(get_data_section);
use List::MoreUtils qw(any);
use Plack::Runner;

our $VERSION = '0.01';

sub new {
    my ($class, @args) = @_;

    my $self = bless {
        args => \@args,
        clients => {},
        ansi => HTML::FromANSI::Tiny->new(
            auto_reverse  => 1,
            no_plain_tags => 1,
        ),
    }, $class;

    $self->{in} = AnyEvent::Handle->new(
        fh => \*STDIN,
        on_read => sub {
            my $handle = shift;
            $handle->push_read(line => sub {
                my ($handle, $line) = @_;
                foreach (keys %{ $self->{clients} }) {
                    my $client = $self->{clients}->{$_};
                    if ($client->{handle}->destroyed) {
                        delete $self->{clients}->{$_};
                        next;
                    }
                    $self->push_line($client->{handle}, "$line\n");
                }
            }) if any { not $_->{handle}->destroyed } values %{ $self->{clients} };
        },
        on_error => sub {
            my ($handle, $fatal, $message) = @_;
            $self->{left} = $handle->rbuf;
            warn "stdin: $message\n";
        }
    );

    return $self;
}

sub boundary {
    my $self = shift;
    return $self->{boundary} ||= join '', 'htmlcat', $$, time;
}

sub push_line {
    my ($self, $handle, $line) = @_;
    $handle->push_write("Content-Type: application/json\n\n");
    $handle->push_write(json => { html => scalar $self->{ansi}->html($line) });
    $handle->push_write('--' . $self->boundary . "\n");
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
                    200,
                    [ 'Content-Type' => sprintf 'multipart/mixed; boundary="%s"', $self->boundary ]
                ]);
                $writer->write('--' . $self->boundary . "\n");

                my $io = $env->{'psgix.io'};
                my $handle = AnyEvent::Handle->new(
                    fh => $io,
                    on_error => sub {
                        my ($handle, $fatal, $message) = @_;
                        warn "client [$remote_addr]: $message\n";
                    }
                );

                if ($self->{in}->destroyed) {
                    if (defined $self->{left}) {
                        while ($self->{left} =~ s/^([^\n]*\n?)// && length $1) {
                            $self->push_line($handle, $1);
                        }
                        delete $self->{left};
                    }
                } else {
                    $self->{clients}->{ 0+$io } = {
                        handle => $handle,
                        writer => $writer, # keep reference
                    };
                }
            };
        } elsif ($env->{PATH_INFO} eq '/css') {
            return [ 200, [ 'Content-Type' => 'text/css' ], [ $self->{ansi}->css ] ];
        } elsif ($env->{PATH_INFO} eq '/') {
            return [ 200, [ 'Content-Type' => 'text/html' ], [ get_data_section('html') ] ];
        } else {
            return [ 404, [], [] ];
        }
    };
}

sub run {
    my $self = shift;
    my $runner = Plack::Runner->new(app => $self->as_psgi);
    $runner->parse_options('--env', 'production', @{ $self->{args} });

    if (my $exec = { @{$runner->{options}} }->{exec}) {
        push @{ $runner->{options} }, server_ready => sub {
            my ($args) = @_;
            my $host  = $args->{host} || 'localhost';
            my $proto = $args->{proto} || 'http';
            system "$exec $proto://$host:$args->{port}/";
        };
    }

    $runner->run;
}

__DATA__

@@ html
<!DOCTYPE html>
<html>
<head>
<title>htmlcat</title>
<link rel="stylesheet" type="text/css" href="/css">
<script type="text/javascript" src="https://raw.github.com/gist/286747/mxhr.js"></script>
<script type="text/javascript">
window.onload = function () {
    var mxhr = new MXHR();
    mxhr.listen('application/json', function (json) {
        var data = eval('(' + json + ')');

        if (!data || !data.html) {
            return;
        }

        if (window.scrollY + document.documentElement.clientHeight >= document.documentElement.scrollHeight) {
            var scrollToBottom = true;
        }

        var div = document.createElement('div');
        div.innerHTML = data.html;

        var out = document.getElementById('out');
        while (div.firstChild) {
            out.appendChild(div.firstChild);
        }

        document.title = data.html.replace(/<.*?>/g, '') + ' - htmlcat';

        if (scrollToBottom) {
            window.scrollTo(0, document.body.scrollHeight);
        }
    });
    mxhr.open('GET', '/stream', true);
    mxhr.send('');
};
</script>
</head>
<body>
<pre id="out"></pre>
</body>
</html>

__END__

=head1 NAME

App::htmlcat -

=head1 SYNOPSIS

  use App::htmlcat;

=head1 DESCRIPTION

App::htmlcat is

=head1 AUTHOR

motemen E<lt>motemen@gmail.comE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
