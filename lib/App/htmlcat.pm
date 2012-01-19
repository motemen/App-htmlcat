package App::htmlcat;
use strict;
use warnings;
use AnyEvent::Handle;
use HTML::FromANSI::Tiny;
use HTML::Entities;
use Data::Section::Simple qw(get_data_section);
use IO::Socket::INET;
use Plack::Runner;

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
            $self->broadcast($_[0]{rbuf});
            exit 1;
        }
    );

    return $self;
}

sub on_read {
    my $self = shift;

    return sub {
        my ($handle) = @_;
        $self->broadcast($handle->rbuf);
        $handle->rbuf = '';
    };
}

sub broadcast {
    my ($self, $data) = @_;

    open my $fh, '<:utf8', \$self->{in}->rbuf;
    while (<$fh>) {
        foreach my $client (values %{ $self->{clients} }){ 
            $self->push_line($client->{handle}, $_);
        }
    }
}

sub boundary {
    my $self = shift;
    return $self->{boundary} ||= join '_', 'htmlcat', $$, time;
}

sub push_line {
    my ($self, $handle, $line) = @_;
    $handle->push_write("Content-Type: application/json; charset=utf-8\n\n");
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
                    [ 'Content-Type' => sprintf 'multipart/mixed; charset=utf-8; boundary="%s"', $self->boundary ]
                ]);
                $writer->write('--' . $self->boundary . "\n");

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
                $self->{in}->on_read($self->on_read);
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
        '--port' => empty_port(),
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

sub empty_port {
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

@@ js
// https://gist.github.com/286747
/* 
	// mxhr.js
	// BSD license

	var mxhr = new MXHR;
	mxhr.listen(mime, function(body){ process(body) });
	mxhr.listen('complete', function(status_code){ ... }); // 2xx response
	mxhr.listen('error', function(status_code){ ... });    // other case
	mxhr.open("GET", url, true); // or mxhr.open("POST", url, true);
	mxhr.send("");
*/

function MXHR() {
	this.req = new XMLHttpRequest;
	this.listeners = {};
	this.watcher_interval = 15;
	this.parsed = 0;
	this.boundary;
	this._watcher_id = null;
}

(function(p){
	function open(){
		var self = this;
		var res = this.req.open.apply(this.req, arguments);
		this.req.onreadystatechange = function(){
			if (self.req.readyState == 3 && self._watcher_id == null) { self.init_stream() }
			if (self.req.readyState == 4) { self.finish_stream(self.req.status) }
		};
		return res;
	}
	function send(){
		return this.req.send.apply(this.req, arguments);
	}
	function init_stream(){
		var self = this;
		var contentTypeHeader = this.req.getResponseHeader("Content-Type");
		if (contentTypeHeader.indexOf("multipart/mixed") == -1) {
			this.req.onreadystatechange = function() {
				self.req.onreadystatechange = function() {};
				self.invoke_callback('error', self.req.status);
			}
		} else {
			this.boundary = '--' + contentTypeHeader.split('"')[1];
			this.start_watcher();
		}
	}
	function finish_stream(status){
		this.stop_watcher();
		this.process_chunk();
		if (status >= 200 && status < 300) {
			this.invoke_callback('complete', status);
		} else {
			this.invoke_callback('error', status);
		}
	}
	function start_watcher() {
		var self = this;
		this._watcher_id = window.setInterval(function(){
			self.process_chunk();
		}, this.watcher_interval);
	}
	function stop_watcher() {
		window.clearInterval(this._watcher_id);
		this._watcher_id = null;
	}
	function listen(mime, callback){
		if(typeof this.listeners[mime] == 'undefined') {
			this.listeners[mime] = [];
		}
		if(typeof callback != 'undefined' && callback.constructor == Function) {
			this.listeners[mime].push(callback);
		}
	}
	function process_chunk(){
		var length = this.req.responseText.length;
		var rbuf = this.req.responseText.substring(this.parsed, length);
		// [parsed_length, header_and_body]
		var res = this.incr_parse(rbuf);
		if (res[0] > 0) {
			this.process_part(res[1]);
			this.parsed += res[0];
			if (length > this.parsed) this.process_chunk();
		}
	}
	function process_part(part) {
		var self = this;
		part = part.replace(this.boundary + "\n", '');
		var lines = part.split("\n");
		var mime = lines.shift().split('Content-Type:', 2)[1].split(";", 1)[0].replace(' ', '');
		mime = mime ? mime : null;
		var body = lines.join("\n");
		this.invoke_callback(mime, body);
	}
	function invoke_callback(mime, body) {
		var self = this;
		if(typeof this.listeners[mime] != 'undefined') {
			this.listeners[mime].forEach(function(cb) {
				cb.call(self, body);
			});
		}
	}
	function incr_parse(buf) {
		if (buf.length < 1) return [-1];
		var start = buf.indexOf(this.boundary);
		if (start == -1) return [-1];
		var end = buf.indexOf(this.boundary, start + this.boundary.length);
		// SUCCESS
		if (start > -1 && end > -1) {
			var part = buf.substring(start, end);
			// end != part.length in wrong response, ignore it
			return [end, part];
		}
		// INCOMPLETE
		return [-1];
	}
	var methods = "open,send,init_stream,finish_stream,start_watcher,stop_watcher,listen," +
	 			  "process_chunk,process_part,invoke_callback,incr_parse";
	eval(
		methods.split(",").map(function(v){
			return 'p.'+v+'='+v+';'
		}).join("")
	);
})(MXHR.prototype);

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
