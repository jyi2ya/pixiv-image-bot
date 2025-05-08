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
use Mojo::Log;
use DDP;
use List::Util;

use Env qw{
$DATAFILE
$SENT_KEEP_RATIO
$ONEBOT_API
$ONEBOT_API_TOKEN
@TARGET_GROUP_ID
$TIME_BUDGET
@TAGS_BLACKLIST
$TAGS_BLACKLIST_THRESHOLD
$DEEPDANBOORU_API
$MAX_PUSH_TAGS
};

my $UA = Mojo::UserAgent->new;
my $LOG = Mojo::Log->new;

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

sub get_image_tags($image_b64) {
    my $resp = $UA->post(
        Mojo::URL->new($DEEPDANBOORU_API)->path('tag'), json => {
            image => $image_b64
        }
    );
    $resp->result->json;
}

sub send_one ($data) {
    my $to_send = shift @{ $data->{queued} };
    die 'empty queue' unless defined $to_send;
    $LOG->info("sending: $to_send");
    push @{ $data->{sent} }, $to_send;

    my $image_result;
    my $image_bytes;

    for my $try (1..3) {
        $LOG->info("try fetching image ($try/3)...");
        $image_result = $UA->get($to_send)->result;
        $image_bytes = $image_result->body;
        if ($image_result->is_success) {
            $LOG->info("OK");
            last;
        } else {
            $LOG->warn("failed to get image: $image_bytes");
        }
    }

    my $image_b64 = Mojo::Util::b64_encode $image_bytes;
    my $image_tags = get_image_tags($image_b64);

    for my $blocked_tag (@TAGS_BLACKLIST) {
        if (exists($image_tags->{$blocked_tag}) and $image_tags->{$blocked_tag} >= $TAGS_BLACKLIST_THRESHOLD) {
            $LOG->info("unwanted tag detected: [$blocked_tag], will not push");
            return;
        }
    }

    my @top_tags = reverse sort { $a->[1] <=> $b->[1] } List::Util::pairs %$image_tags;
    my @took_tags = @top_tags[0..(List::Util::min($MAX_PUSH_TAGS, $#top_tags))];
    my $tags_text = join ", ", map {
        my ($tag, $confidence) = @$_;
        sprintf "%s(%.2f)", $tag, $confidence;
    } @took_tags;

    for my $group_id (@TARGET_GROUP_ID) {
        eval {
            my $resp = $UA->post(
                Mojo::URL->new($ONEBOT_API)->path('/send_group_msg') => {
                    Authorization => "Bearer $ONEBOT_API_TOKEN",
                }, json => {
                    group_id => $group_id,
                    message => [
                        {
                            type => 'image',
                            data => {
                                file => "base64://$image_b64",
                            }
                        },
                        {
                            type => 'text',
                            data => {
                                text => "\n$tags_text",
                            },
                        }
                    ]
                }
            );
            my $result = $resp->result;
            die $result->text unless $result->is_success;
            my $json = $result->json;
            die $json->{message} if $json->{status} ne 'ok';
        };
        if ($@) {
            $LOG->warn("failed to send to group $group_id: $@");
        }
    }
}

sub main {
    for (;;) {
        my $data = load_data($DATAFILE);
        eval { send_one($data) };
        if ($@) {
            $LOG->warn("failed to send image: $@");
        } else {
            $LOG->info("push ok");
        }
        while (@{ $data->{sent} } > $SENT_KEEP_RATIO * @{ $data->{queued} }) {
            shift @{ $data->{sent} };
        }
        store_data($DATAFILE, $data);
        my $to_sleep = $TIME_BUDGET / (@{ $data->{queued} } || 1);
        $LOG->info("will sleep: $to_sleep");
        sleep $to_sleep;
    }
}

main unless caller;
