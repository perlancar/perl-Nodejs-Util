package Data::Sah::Util::JS;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(get_nodejs_path);

# check availability of the node.js executable, return the path to executable or
# undef if none is available. node.js is normally installed as 'node', except on
# debian ('nodejs').
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
# ABSTRACT: Utilities related to JavaScript

=head1 FUNCTIONS

None exported by default.

=head2 get_nodejs_path() => str

=cut
