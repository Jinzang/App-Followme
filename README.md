# NAME

App::Followme - Update a static website

# SYNOPSIS

    use App::Followme;
    my $app = App::Followme->new($configuration);
    $app->run(shift @ARGV);

# DESCRIPTION

This is the module that is run by the followme script. It loads and runs
all the other modules. When it is run, it searches the directory path for
configuration files. The topmost file defines the top directory of the website.
It reads each configuration file it finds and then starts updating the directory
passed as an argument to run, or if no directory is passed, the directory the
followme script is run from.

Configuration file lines are organized as lines containing

    NAME = VALUE

and may contain blank lines or comment lines starting with a `#`. Values in
configuration files are combined with those set in the files in directories
above it.

The module parameter contains the name of a module to be run on the directory
containing the configuration file and possibly its subdirectories. It must have
new and run methods. An object is created by calling the new method with the
configuration. The run method is then called without arguments. The run method
returns a value, which if true indicates that module should be run in the
subdirectories of the current directory.

# LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Bernie Simon <bernie.simon@gmail.com>
