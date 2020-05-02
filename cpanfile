requires 'perl', '5.008001';
requires 'Test::Requires', 0;
requires 'YAML::Tiny', '1.60';
requires 'Time::Format', '1.04';
requires 'Time::Local', '1.18';
requires 'File::Spec::Functions', '3.75';
requires 'File::Path', '2.16';
requires 'Digest::MD5', '2.55';

recommends 'Image::Size', 3.300;
recommends 'Net::FTP', '0';
recommends 'Text::Markdown', '1.000031';
recommends 'Pod::Simple::XHTML', '3.20';

on 'test' => sub {
    requires 'Test::More', '0.98';
    requires => 'Test::Requires', 0;
};
