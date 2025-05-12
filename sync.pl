#!/usr/bin/env perl
use 5.020;
use utf8;
use warnings;
use autodie;
use feature qw/signatures postderef/;
no warnings qw/experimental::postderef/;

use Mojo::UserAgent;
use Mojo::Util;
use Mojo::DOM;
use Mojo::File;
use Mojo::JSON;
use Mojo::URL;
use DDP;

use Env qw/
$DATAFILE
$RSS_URL
@RSS_CHANNELS
/;

my $UA = Mojo::UserAgent->new;
my @RSS = map { Mojo::URL->new($RSS_URL)->path($_) } @RSS_CHANNELS;

sub load_data ($path) {
    my $result = eval {
        my $content = Mojo::File->new($path)->slurp;
        Mojo::JSON::decode_json($content)
    };
    $result // {
        queued => [],
        sent => [],
    };
}

sub store_data ($path, $data) {
    my $content = Mojo::JSON::encode_json($data);
    Mojo::File->new($path)->spurt($content);
}

sub main {
    my $data = load_data($DATAFILE);
    my %marked = map { $_ => undef } @{ $data->{sent} }, @{ $data->{queued} };
    my @new;
    for my $url (@RSS) {
        my $resp = $UA->get($url);
        my $content = $resp->result->text;
        my $feed = Mojo::DOM->new($content);
        my @images = ();
        for my $desc ($feed->find('description')->@*) {
            my $inner = $desc->child_nodes->first;
            if ($inner->type eq 'cdata') {
                my $entry = Mojo::DOM->new($inner->content);
                for my $image ($entry->find('img')->@*) {
                    my $link = $image->attr('src');
                    if (!exists($marked{$link})) {
                        push @new, $link;
                        push @{$data->{queued}}, $image->attr('src');
                    }
                }
            }
        }
    }
    store_data($DATAFILE, $data);
    for my $link (@new) {
        my $prefetch_cache = $UA->get($link);
    }
}

main unless caller;
