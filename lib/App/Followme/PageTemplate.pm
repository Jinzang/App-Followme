package App::Followme::PageTemplate;
use 5.008005;
use strict;
use warnings;

our $VERSION = "0.89";

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(compile_template);

#----------------------------------------------------------------------
# Compile the template into a subroutine

sub compile_template {
    my ($template, $variable) = @_;
    $variable = '{{*}}' unless $variable;
    
    my ($left, $right) = split(/\*/, $variable);
    $left = quotemeta($left);
    $right = quotemeta($right);
    
    my $code = <<'EOQ';
sub {
my ($data) = @_;
my ($block, @blocks);
EOQ

    my @tokens = split(/(<!--\s*(?:loop|endloop).*?-->)/, $template);
    
    foreach my $token (@tokens) {
        if ($token =~ /^<!--\s*loop/) {
            $code .= 'foreach my $data (@{$data->{loop}}) {' . "\n";

        } elsif ($token =~ /^<!--\s*endloop/) {
            $code .= "}\n";

        } else {
            $code .= "\$block = <<'EOQ';\n";
            $code .= "${token}\nEOQ\n";
            $code .= "chomp \$block;\n";
            $code .= "\$block =~ s/$left(\\w+)$right/\$data->{\$1}/g;\n";
            $code .= "push(\@blocks,\$block);\n";
        }
    }
    
    $code .= <<'EOQ';
return join('', @blocks);
}
EOQ

    my $sub = eval ($code);
    die $@ unless $sub;
    return $sub;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::PageTemplate - Simple templating for page creation

=head1 SYNOPSIS

    use App::Followme::PageTemplate qw(compile_template);
    my $method = compile_template($template);
    my $page = $method->($data);

=head1 DESCRIPTION

This package includes one function, compile_template. It compiles a template
contained in a string into a subroutine. Then the subroutine is called with one
argument, a hash containing the data to be interpolated into the subroutine. The
output is a page containing the template with the interpolated data. The data
supplied to the subroutine should be a hash reference. fields in the hash are
substituted into variables in the template. Variables in the template are
surrounded by double braces, so that a link would look like:

    <li><a href="{{url}}">{{title}}</a></li>

The string which indicates a variable is passed as an optional second argument
to compile_template. If not present or blank,double braces are used. If present,
the string should contain an asterisk to indicate where the variable name is
placed.

The data hash may contain a list of hashes, which should be named loop. Text
in between loop comments will be repeated for each hash in the list and each
hash will be interpolated into the text. Loop comments look like

    <!-- loop -->
    <!-- endloop -->

There should be only one pair of loop comments in the template. 

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

