package Nodejs::Util;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(get_nodejs_path);

sub get_nodejs_path {
    require File::Which;

    my $path;
    for my $name (qw/nodejs node/) {
        $path = File::Which::which($name);
        next unless $path;

        # check if it's really nodejs
        my $cmd = "$path -e 'console.log(1+1)'";
        my $out = `$cmd`;
        if ($out =~ /\A2\n?\z/) {
            return $path;
        } else {
            #say "D:Output of $cmd: $out";
        }
    }
    return undef;
}

1;
# ABSTRACT: Utilities related to Node.js

=head1 FUNCTIONS

None exported by default.

=head2 get_nodejs_path() => str

Check availability of the Node.js executable in the PATH. Return the path to
executable or undef if none is available. Node.js is usually installed as 'node'
or 'nodejs'.

=cut
