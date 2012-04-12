# NAME

htmlcat - stdin to your browser

# SYNOPSIS

    $ command-that-prints-to-stdout | htmlcat --exec=open

# DESCRIPTION

htmlcat shows stdin in HTML, by establishing a temporary HTTP server.

# FEATURES

 * Highlights ANSI code in HTML
 * Real-time stdin stream to browsers
 * Support for multiple clients

# OPTION

 * --exec=_command_

Invokes _command_ with the URL htmlcat listens as the only argument.
Typically a command which opens a browser would be useful.

# AUTHOR

motemen <motemen@gmail.com>

# THANKS TO

mala

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
