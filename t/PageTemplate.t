#!/usr/bin/env perl
use strict;

use IO::File;
use Test::More tests => 4;
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::PageTemplate;

#----------------------------------------------------------------------
# Test converters

do {
   my $text = <<'EOQ';
<p>This is a paragraph</p>

<pre>
This is preformatted text.
</pre>
EOQ

   my $template = <<'EOQ';
<html>
<head>
<meta name="robots" content="archive">
<!-- section meta -->
<title>{{title}}</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>{{title}}</h1>

{{body}}

<ul>
<!-- loop -->
<li>{{count}} {{item}}</li>
<!-- endloop -->
</ul>
<!-- endsection content -->
</body>
</html>
EOQ

    my @loop;
    my $i = 0;
    foreach my $word (qw(one two three four)) {
        $i = $i + 1;
        push(@loop, {count => $i, item => $word});
    }
    
    my $data = {title =>'Three', body => $text, loop => \@loop};
    my $sub = App::Followme::PageTemplate::compile_template($template);
    my $page = $sub->($data);

    ok($page =~ /<h1>Three<\/h1>/, 'Apply template to title'); # test 1
    ok($page =~ /<p>This is a paragraph<\/p>/, 'Apply template to body'); # test 2

    my @li = $page =~ /(<li>)/g;
    is(@li, 4, 'Loop over data items'); # test 3
    ok($page =~ /<li>2 two<\/li>/, 'Substitute in loop'); # test 4
};

