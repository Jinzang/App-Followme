requires 'perl', '5.008001';
requires 'Test::Requires', 0;
requires 'YAML::Tiny', '1.60';
requires 'Time::Format', '1.04';
requires 'Time::Local', '1.18';

recommends 'GD', 2.21;
recommends 'Net::FTP', '0';
recommends 'Text::Markdown', '1.000031';

on 'test' => sub {
    requires 'Test::More', '0.98';
    requires => 'Test::Requires', 0;
};
