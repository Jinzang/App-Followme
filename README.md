# NAME

App::Followme - A template-less html templating system

# SYNOPSIS

    use App::Followme;
    followme('htm');

# DESCRIPTION

Followme is an html template processsor where every file is the template. It
takes the mose recently changed html file in the current directory as the
template and modifies the other html files in the directory to match it. Every
file has blocks of code surrounded by comments that look like

    <!-- begin name-->
    <!-- end name -->

The new page is the template file with all the named blocks replaced by the
corresponding block in the old page. The effect is that all the code outside 
the named blocks are updated to be the same across all the html pages.

This module exports one function, followme. It takes one or no arguments. If
an argument is given, it is the extension used on all the html files. If no
argument is given, the extension is taken to be html.

# LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Bernie Simon <bernie.simon@gmail.com>
