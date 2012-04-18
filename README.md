# NAME

htmlcat - stdin to your browser

# SYNOPSIS

    $ command-that-prints-to-stdout | htmlcat --exec=open

# DESCRIPTION

`htmlcat` renders stdin in HTML, by establishing a temporary HTTP server.

Requires modern browser that recognize [Server-Sent Events](http://dev.w3.org/html5/eventsource/).

# FEATURES

 * Highlights ANSI code in HTML
 * Real-time stdin stream to browsers
 * Support for multiple clients

# OPTION

 * --exec=_command_

Invokes _command_ with the URL `htmlcat` listens as the only argument.
Typically a command which opens a browser would be useful.

 * --host=_host_, --port=_port_

Specifies the host or port to listen. Actually they are
handled by [Plack::Runner](http://search.cpan.org/perldoc?Plack::Runner), so `htmlcat` does nothing with them.

# AUTHOR

motemen <motemen@gmail.com>

# THANKS TO

mala, for Server-sent events implementation

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
