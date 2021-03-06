package DDGC::DB::ResultSet::InstantAnswer;
# ABSTRACT: Resultset class for Instant Answer Pages

use Moose;
extends 'DDGC::DB::Base::ResultSet';
use namespace::autoclean;

sub ia_index_hri {
    my ( $self, $limit, $last ) = @_;
    my $ial = $self->search(
        {'topic.name' => [{ '!=' => 'test' }, { '=' => undef}],
         'me.perl_module' => { -not_like => 'DDG::Goodie::IsAwesome::%' },
         'me.dev_milestone' => { '=' => 'live'},
        },
        {
            prefetch => { instant_answer_topics => 'topic' },
            'select' => [
                qw/ name repo src_name
                    dev_milestone description
                    template meta_id perl_module
                    live_date created_date
                /, ],
             'as' => [
                qw/ name repo src_name
                    dev_milestone description
                    template id perl_module
                    live_date created_date
                /, ],
            collapse => 1,
        },
    )->hri
     ->order_by( 'me.name' );

    $ial = $ial->rows( $limit ) if $limit;
    $ial = $ial->search( {
       'me.name' => { '>' => $last },
    } ) if $last;

    return $ial->all_ref;
}

1;
