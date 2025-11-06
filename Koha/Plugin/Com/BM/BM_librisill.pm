package Koha::Plugin::Com::BM::BM_librisill;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use C4::Auth;
use C4::Context;
use C4::Search;
use C4::Auth qw( get_template_and_user );
use C4::Output qw( output_html_with_http_headers );
use C4::Biblio qw( AddBiblio ModBiblio DelBiblio );
use C4::Reserves qw( AddReserve ModReserve);

use utf8;
use URI;
use Koha::Logger;

use Koha::Account::Lines;
use Koha::Account;
use Koha::Database;
use Koha::DateUtils qw( dt_from_string );
use Koha::Item;
use Koha::Items;
use Koha::Holds;
use Koha::Libraries;
use Koha::Patron::Categories;
use Koha::Patron;
use Koha::Patrons;

use LWP::Simple;
use HTTP::Request;

use Cwd qw(abs_path);
use Data::Dumper;
use LWP::UserAgent;
use MARC::Record;

use URI::Escape qw(uri_unescape);
use JSON;

use YAML;

use POSIX qw(strftime);

use strict;
use warnings;


## Here we set our plugin version
our $VERSION = "0.2.9";
our $MINIMUM_VERSION = "24.11";

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'BM Libris ILL module',
    author          => 'Johan Sahlberg',
    date_authored   => '2025-09-23',
    date_updated    => "2025-11-06",
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
    description     => 'Module for ILL',
    namespace       => 'bm_librisill',
};

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}



sub intranet_js {
    my ( $self ) = @_;    

    return q|
        <script>           

            var searchILL_link = '/cgi-bin/koha/plugins/run.pl?class=' + encodeURIComponent("Koha::Plugin::Com::BM::BM_librisill") + '&method=searchILL';

            $(`
                <li class="nav-item">
                    <a class="nav-link" href="${searchILL_link}">
                        <span class="nav-link-text">Fjärrlån</span>
                    </a>
                </li>
            `).appendTo('#toplevelmenu');

            if ($('#main_intranet-main').length) {
                $('.biglinks-list:first').append(`
                    <li>
                    <a class="icon_general icon_fjarrlan" href="${searchILL_link}">
                        <i class="fa fa-fw fa fa-envelope"></i>
                    Fjärrlån
                    </a>
                </li>
                `);
            }            

        </script>

    |;
    
}


sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $token = $self->retrieve_data('token');

    my $itemtype   = $self->retrieve_data('itemtype');
    my $ccode      = $self->retrieve_data('ccode');
    my $notforloan = $self->retrieve_data('notforloan');
    my $loc        = $self->retrieve_data('loc');

    warn "Config saved: " . $itemtype . ' ' . $ccode . ' ' . $notforloan . ' ' . $loc;
    
     
    unless ( $cgi->param('save') && $cgi->param('token') eq $token ) {
        my $template = $self->get_template({ file => 'configure.tt' });

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            apikeys   => $self->retrieve_data('apikeys'),
            itemtypes => Koha::ItemTypes->search(undef, { order_by => { -asc => ['description'] }})->unblessed,
            ccodeav => Koha::AuthorisedValues->search({ category => 'CCODE' }, { order_by => { -asc => ['lib'] }})->unblessed,
            notforloanav => Koha::AuthorisedValues->search({ category => 'NOT_LOAN' }, { order_by => { -asc => ['lib'] } })->unblessed,
            locav => Koha::AuthorisedValues->search({ category => 'LOC' }, { order_by => { -asc => ['lib'] }})->unblessed,
            ill_itemtype    => $itemtype,
            ill_ccode       => $ccode,
            ill_notforloan  => $notforloan,
            ill_loc         => $loc, 
            token           => $token,
        );

        $self->output_html( $template->output() );
    }
    else {
        $self->store_data(
            {
                apikeys     => $cgi->param('apikeys'),
                itemtype    => $cgi->param('default-itemtype'),
                ccode       => $cgi->param('default-ccode'),
                notforloan  => $cgi->param('default-notforloan'),
                loc         => $cgi->param('default-location'),                
                token       => $token,               
            }
        );
        $self->go_home();
    }
    
}



sub install() {
    my ( $self, $args ) = @_;

    unless ($self->retrieve_data('token')) {
        use Bytes::Random::Secure qw(random_bytes_base64);

        $self->store_data({'token' => random_bytes_base64(16, '')});
    }
}



sub getLibrisKey {
    
    my ( $self ) = @_;

    my $branch;
    if (C4::Context->userenv) {
        $branch = C4::Context->userenv->{'branch'};
    }
    my $branch_fixed = join '', map { ucfirst lc $_ } split /(\s+)/, $branch;

    my $yaml_keys = Load( $self->retrieve_data('apikeys') );

    my $libris_key = $yaml_keys->{$branch_fixed};

    return $libris_key;

}


sub flstatus {
    my ( $self, $ill_id, $start, $end ) = @_;
    
    my $branch;
    if (C4::Context->userenv) {
        $branch = C4::Context->userenv->{'branch'};
    }
    my $branch_fixed = join '', map { ucfirst lc $_ } split /(\s+)/, $branch;

    my $ua = new LWP::UserAgent;
    $ua->agent("Koha ILL");

    # Setup variables
    my $string = "librisfjarrlan/api/illrequests";
    my $host = "iller.libris.kb.se";
    my $protocol = "https";
    my $libris_key = getLibrisKey( $self ); 

    my $error;
    
    if ( !$libris_key ) {
        my %err = (
            error => 'API-nyckel saknas för sigel',
        );

        $error = encode_json( \%err );

        return $error;
    }

    # Build the url
    my $url;    
    
    if (length($ill_id) > 1) {
        $url = "$protocol://$host/$string/$branch_fixed/$ill_id";

        warn "med ILL_id"
    } else {
        $url = "$protocol://$host/$string/$branch_fixed/outgoing?start_date=$start&end_date=$end";
        warn "EJ ILL_id"
    }     
    
    # Fetch the actual data from the query
    my $request = HTTP::Request->new("GET" => $url);

    $request->header( 'api-key' => $libris_key );

    my $response = $ua->request($request);

    my $jsonString = $response->content;

    return $jsonString;

}



sub searchILL {
    my ( $self, $args ) = @_;

    my $query = CGI->new;

    my ( $template, $loggedinuser, $cookie, $flags ) = get_template_and_user(
        {
            template_name   => $self->mbf_path("search_ill.tt"),
            query           => $query,
            type            => "intranet",
            flagsrequired   => { circulate => "circulate_remaining_permissions" },
        }
    );    

    my $branch;
    if (C4::Context->userenv) {
        $branch = C4::Context->userenv->{'branch'};
    }
    my $branch_fixed = join '', map { ucfirst lc $_ } split /(\s+)/, $branch;

    my $ill_id_offset = length( $branch_fixed ) + 12;
    
    warn "Offset: " . $ill_id_offset;

    my $itemtype = $self->retrieve_data('itemtype');
    my $ccode = $self->retrieve_data('ccode');
    my $notforloan = $self->retrieve_data('notforloan');
    
    my $dbh   = C4::Context->dbh;

    my $ills = $dbh->selectall_arrayref("
    
SELECT DISTINCT 
    items.dateaccessioned, 
    items.itemnumber,
    biblio.biblionumber,
    biblio.title, 
    biblio.author, 
    borrowers.borrowernumber, 
    borrowers.surname, 
    borrowers.firstname, 
    CASE
        
        WHEN items.homebranch='$branch_fixed' AND LOCATE ('$branch_fixed-', itemnotes_nonpublic) > 0
        THEN SUBSTRING(itemnotes_nonpublic, LOCATE ('$branch_fixed-', itemnotes_nonpublic), $ill_id_offset)

    ELSE
        NULL
    END 

FROM 
    biblio 

JOIN 
    items ON (items.biblionumber=biblio.biblionumber) 
    LEFT JOIN reserves ON (reserves.biblionumber=biblio.biblionumber) 
    LEFT JOIN borrowers ON (borrowers.borrowernumber=reserves.borrowernumber) 

WHERE 
    items.itype = '$itemtype' 
    AND (items.notforloan = '$notforloan' OR items.notforloan = '-4')
    AND items.homebranch = '$branch'    

ORDER BY items.dateaccessioned DESC

;");

    my @ill_mappings = ();
    my @items = ();
    
    for my $ill (@$ills) {

        my $item = Koha::Items->find( $ill->[1] );

        push @ill_mappings, {
            dateaccessioned => $ill->[0],
            itemnumber => $ill->[1],
            biblionumber => $ill->[2],
            title => $ill->[3],
            author  => $ill->[4],
            borrowernumber  => $ill->[5],
            surname  => $ill->[6],
            firstname  => $ill->[7],
            ill_id => $ill->[8],                
            barcode => $item->barcode,
            itemnotes => $item->itemnotes,
            itemnotes_nonpublic => $item->itemnotes_nonpublic,
            notforloan => $item->notforloan,
        };        
    }

    my $total = scalar @ill_mappings;
    
    my $ill_requests = ();
    my @ill_libraries = ();

    my $error;

    my @ill_ids = ();
    

    if ( $total > 0 ) {

        for my $id ( @ill_mappings ) {

            if ( $id->{ill_id} ) {
            
                my $sigellength = length($id->{ill_id}) - 12;

                push @ill_ids, {
                    date => '20' . substr($id->{ill_id}, ($sigellength + 1), 2) . '-' . substr($id->{ill_id}, ($sigellength + 3), 2) . '-' . substr($id->{ill_id}, ($sigellength + 5), 2),
                }
            } else {
                warn "No ID!";
            }

        }

        warn "Length of IDs: " . scalar @ill_ids ;

        my $start;
        my $end;
        

        if ( scalar @ill_ids > 0 ) {
            @ill_ids = sort { $b->{date} cmp $a->{date} } @ill_ids;

            $end = $ill_ids[0]->{date};
            if ( $total == 1 ) {
                $start = $end;
            } else {
                $start = $ill_ids[-1]->{date};
            }

            warn "Start and end: " . $start . ' | ' . $end;

            my @pos = ('8','5');
            
            for my $po (@pos) {
                if (substr($end, $po, 1 ) eq '0') {
                    substr($end, $po, 1 ) = "";
                }
                if (substr($start, $po, 1 ) eq '0') {
                    substr($start, $po, 1 ) = "";
                }
            }

            my $ill_id = "0";

            my $statuses = flstatus( $self, $ill_id, $start, $end );

            my $status_decoded = decode_json( $statuses );

            if ( $status_decoded->{'error'} ) {
                $error = $status_decoded->{'error'};
                warn "Error: " . $error;
            } else {

                $ill_requests = $status_decoded->{'ill_requests'};

                my @ill_sigels;

                for my $ill ( @$ill_requests ) {
                    if ( grep{$_->{'ill_id'} eq $ill->{'lf_number'}} @ill_mappings )  {
                        unless (grep{$_ eq $ill->{'active_library'}} @ill_sigels) {
                            push (@ill_sigels, $ill->{'active_library'});
                            warn "Ill sigel: " . $ill->{'active_library'};
                        }
                    }
                }
            
                my $sigel = join("," , @ill_sigels);

                my $libdataJSON = getlibdata( $self, $sigel);
                my $libdata = decode_json( $libdataJSON );
                my $lib = $libdata->{'libraries'};

                for my $ill ( @$ill_requests ) {

                    if ( grep{$_->{'ill_id'} eq $ill->{'lf_number'}} @ill_mappings )  {

                        for my $li ( @$lib ) {

                            if ( $li->{'library_code'} eq $ill->{'active_library'}) {
                                push (@ill_libraries, {
                        
                                    sigel        => $ill->{'active_library'},
                                    libraryname  => $li->{'name'},
                                    library_id   => $li->{'library_id'},
                        
                                }) unless grep{$_->{'sigel'} eq $ill->{'active_library'}} @ill_libraries;
                            }
                        }
                    }
                }
            }
        }                
    }

    $template->param(
        ill_mappings    => \@ill_mappings,
        ill_requests    => $ill_requests,
        ill_libraries   => \@ill_libraries,
        total           => $total,
        errormessage    => $error,
        plugin_dir      => $self->bundle_path,
    );

    output_html_with_http_headers $query, $cookie, $template->output;    
}


sub save_ILL {
    my ( $self, @args ) = @_;

    my $query = CGI->new;

    my $itemnumber = $query->param('itemnumber');
    my $itemnotes = $query->param('itemnotes');
    my $ill_id = $query->param('ill_id');
    my $barcode = $query->param('barcode');
    my $active_library = $query->param('active_library');

    my $item = Koha::Items->find( $itemnumber );

    $item->barcode( $barcode );
    $item->itemnotes( $itemnotes );
    $item->itemnotes_nonpublic( '+' . $active_library . ' ' . $ill_id );

    $item->notforloan(0)->store;

    $item->store;

    my %errhash = (
        error => 0,        
    );

    if ( $item->barcode ne $barcode ) {        
        $errhash{error} =  1;        
    } 

    my $errorJSON = encode_json( \%errhash );    
    
    my $cgi = CGI->new;
    print $cgi->header(-type => "application/json", -charset => "utf-8");

    print $errorJSON;

}


sub delete_ILL {
    my ( $self, @args ) = @_;

    my $query = CGI->new;

    my $biblionumber = $query->param('biblionumber');
    my $itemnumber = $query->param('itemnumber');
    my $borrowernumber = $query->param('borrowernumber');
    
    my %error = (
        error => 0,
    );

    if ( $biblionumber ) {

        my $holds = Koha::Holds->search({ biblionumber => $biblionumber });
        
        while ( my $hold = $holds->next ) {
            $hold->delete;
        }

        my $items = Koha::Items->search({ biblionumber => $biblionumber });
        my $all_deleted = 1;
        while ( my $item = $items->next ) {
            if ($item->itype eq $self->retrieve_data('itemtype') ) {
                $item->delete;
            } else {
                $all_deleted = 0;
            }
        }
        # Delete the record
        if ($all_deleted) {
            my $delerror = C4::Biblio::DelBiblio( $biblionumber );
        }

    } else {
        $error{error} = 1;
    }
   

    my $errorJSON = encode_json( \%error );

    my $cgi = CGI->new;
    print $cgi->header(-type => "application/json", -charset => "utf-8");

    print $errorJSON;

}


sub checkedout_ILL {
    my ( $self, $args ) = @_;

    my $query = CGI->new;

    my ( $template, $loggedinuser, $cookie, $flags ) = get_template_and_user(
        {
            template_name   => $self->mbf_path("checkedout_ill.tt"),
            query           => $query,
            type            => "intranet",
            flagsrequired   => { circulate => "circulate_remaining_permissions" },
        }
    );

    my $branch;
    if (C4::Context->userenv) {
        $branch = C4::Context->userenv->{'branch'};
    }
    my $branch_fixed = join '', map { ucfirst lc $_ } split /(\s+)/, $branch;

    my $ill_id_offset = length( $branch_fixed ) + 12;
    
    warn "Offset: " . $ill_id_offset;

    my $itemtype = $self->retrieve_data('itemtype');
    my $ccode = $self->retrieve_data('ccode');
    my $notforloan = $self->retrieve_data('notforloan');

    my $dbh   = C4::Context->dbh;

    my $ills = $dbh->selectall_arrayref("

SELECT DISTINCT 
    items.dateaccessioned,
    items.itemnumber,
    issues.date_due,
    issues.renewals_count,
    biblio.biblionumber,
    biblio.title,
    biblio.author,
    borrowers.borrowernumber,
    borrowers.surname,
    borrowers.firstname,    
    CASE
        
        WHEN items.homebranch='$branch_fixed' AND LOCATE ('$branch_fixed-', itemnotes_nonpublic) > 0
        THEN SUBSTRING(itemnotes_nonpublic, LOCATE ('$branch_fixed-', itemnotes_nonpublic), $ill_id_offset)

    ELSE
        NULL
    END
            
FROM 
    items
    LEFT JOIN biblio ON (biblio.biblionumber=items.biblionumber)
    LEFT JOIN issues ON (issues.itemnumber=items.itemnumber)
    LEFT JOIN borrowers ON (borrowers.borrowernumber=issues.borrowernumber)
    
WHERE 
    items.itype = '$itemtype'
    AND items.notforloan = '0'
    AND items.onloan IS NOT NULL
    AND items.homebranch = '$branch'
    
ORDER BY items.dateaccessioned DESC

    ;");

    my @ill_mappings = ();
    my @items = ();

    my $error;
    
    for my $ill (@$ills) {

        my $item = Koha::Items->find( $ill->[1] );

        push @ill_mappings, {
            dateaccessioned => $ill->[0],
            itemnumber => $ill->[1],
            date_due => $ill->[2],
            renewals_count => $ill->[3],
            biblionumber => $ill->[4],
            title => $ill->[5],
            author => $ill->[6],
            borrowernumber => $ill->[7],
            surname => $ill->[8],
            firstname => $ill->[9],
            ill_id => $ill->[10],
        };        
    }

    my $total = scalar @ill_mappings;
    my $ill_requests = ();
    my @ill_libraries = ();
    my @ill_ids = ();
    

    if ( $total > 0 ) {

        for my $id ( @ill_mappings ) {

            if ( $id->{ill_id} ) {
            
                my $sigellength = length($id->{ill_id}) - 12;

                push @ill_ids, {
                    date => '20' . substr($id->{ill_id}, ($sigellength + 1), 2) . '-' . substr($id->{ill_id}, ($sigellength + 3), 2) . '-' . substr($id->{ill_id}, ($sigellength + 5), 2),
                }
            } else {
                warn "No ID!";
            }
        }

        warn "Length of IDs: " . scalar @ill_ids ;

        my $start;
        my $end;


        if ( scalar @ill_ids > 0 ) {
            @ill_ids = sort { $b->{date} cmp $a->{date} } @ill_ids;
        
            $end = $ill_ids[0]->{date};
            if ( $total == 1 ) {
                $start = $end;
            } else {
                $start = $ill_ids[-1]->{date};
            }

            warn "Start and end: " . $start . ' | ' . $end;
            
            my @pos = ('8','5');
            
            for my $po (@pos) {
                if (substr($end, $po, 1 ) eq '0') {
                    substr($end, $po, 1 ) = "";
                }
                if (substr($start, $po, 1 ) eq '0') {
                    substr($start, $po, 1 ) = "";
                }
            }

            my $ill_id = "0";

            my $statuses = flstatus( $self, $ill_id, $start, $end );

            my $status_decoded = decode_json( $statuses );

            if ( $status_decoded->{'error'} ) {
                $error = $status_decoded->{'error'};
                warn "Error: " . $error;
            } else {

                $ill_requests = $status_decoded->{'ill_requests'};

                my @ill_sigels;

                for my $ill ( @$ill_requests ) {
                    if ( grep{$_->{'ill_id'} eq $ill->{'lf_number'}} @ill_mappings )  {
                        unless (grep{$_ eq $ill->{'active_library'}} @ill_sigels) {
                            push (@ill_sigels, $ill->{'active_library'});
                            warn "Ill sigel: " . $ill->{'active_library'};
                        }
                    }
                }
            
                my $sigel = join("," , @ill_sigels);

                my $libdataJSON = getlibdata( $self, $sigel);
                my $libdata = decode_json( $libdataJSON );
                my $lib = $libdata->{'libraries'};

                for my $ill ( @$ill_requests ) {

                    if ( grep{$_->{'ill_id'} eq $ill->{'lf_number'}} @ill_mappings )  {

                        for my $li ( @$lib ) {

                            if ( $li->{'library_code'} eq $ill->{'active_library'}) {
                                push (@ill_libraries, {
                        
                                    sigel        => $ill->{'active_library'},
                                    libraryname  => $li->{'name'},
                                    library_id   => $li->{'library_id'},
                        
                                }) unless grep{$_->{'sigel'} eq $ill->{'active_library'}} @ill_libraries;
                            }
                        }
                    }
                }
            }
        }
    }

    $template->param(
        ill_mappings    => \@ill_mappings,
        ill_requests    => $ill_requests,
        ill_libraries   => \@ill_libraries,
        total           => $total,
        errormessage    => $error,
        plugin_dir      => $self->bundle_path,
    );

    output_html_with_http_headers $query, $cookie, $template->output;    
}


sub deleted_ill {
    my ( $self, $args ) = @_;

    my $query = CGI->new;

    my ( $template, $loggedinuser, $cookie, $flags ) = get_template_and_user(
        {
            template_name   => $self->mbf_path("deleted_ill.tt"),
            query           => $query,
            type            => "intranet",
            flagsrequired   => { circulate => "circulate_remaining_permissions" },
        }
    );

    my $branch;
    if (C4::Context->userenv) {
        $branch = C4::Context->userenv->{'branch'};
    }

    my $itemtype = $self->retrieve_data('itemtype');
    my $ccode = $self->retrieve_data('ccode');
    my $notforloan = $self->retrieve_data('notforloan');

    my $search = $query->param('search');

    my $dbh   = C4::Context->dbh;

    my $ills = $dbh->selectall_arrayref("

SELECT  
    deletedbiblio.timestamp,
    deleteditems.dateaccessioned,
    deleteditems.datelastseen,
    deletedbiblio.author,
    deletedbiblio.title,
    deleteditems.issues,
    deleteditems.barcode,
    deleteditems.itemnotes,
    deleteditems.itemnotes_nonpublic

FROM deletedbiblio
LEFT JOIN deleteditems USING (biblionumber)

WHERE deleteditems.itype = '$itemtype'
  AND deleteditems.homebranch = '$branch'
  AND deletedbiblio.title LIKE CONCAT('%', '$search', '%')

ORDER BY deletedbiblio.timestamp DESC

    ;");

    my @ill_mappings = ();
    
    for my $ill (@$ills) {

        push @ill_mappings, {
            timestamp => $ill->[0],
            dateaccessioned => $ill->[1],
            datelastseen => $ill->[2],
            author => $ill->[3],
            title => $ill->[4],
            issues => $ill->[5],
            barcode => $ill->[6],
            itemnotes => $ill->[7],
            itemnotes_nonpublic => $ill->[8],            
        };        
    }

    my $total = scalar @ill_mappings;
    
    $template->param(
        ill_mappings    => \@ill_mappings,
        total           => $total,
        plugin_dir      => $self->bundle_path,
    );

    output_html_with_http_headers $query, $cookie, $template->output;

}


sub librisill_requests {
    my ( $self, @args ) = @_;

    my $query = CGI->new;

    my ( $template, $loggedinuser, $cookie, $flags ) = get_template_and_user(
        {
            template_name   => $self->mbf_path("librisill-requests.tt"),
            query           => $query,
            type            => "intranet",
            flagsrequired   => { circulate => "circulate_remaining_permissions" },
        }
    );

    my $branch;
    if (C4::Context->userenv) {
        $branch = C4::Context->userenv->{'branch'};
    }

    my $time = time();
    my $end = strftime "%F", localtime;
    my $start = strftime "%F", localtime($time-30*24*60*60);

#    warn "New END: " . $end;
#    warn "New START: " . $start;

    my $branch_fixed = join '', map { ucfirst lc $_ } split /(\s+)/, $branch;

    my $errormessage;
    my $jsonString;
    my $decoded;
    my %titles;
    my %users;
    my %lf_numbers;
    my %bib_ids;

    my $ua = new LWP::UserAgent;
    $ua->agent("Perl API Client/1.0");

    # Setup variables
    my $string="librisfjarrlan/api/illrequests";
    my $host="iller.libris.kb.se";
    my $protocol="https";
    my $libris_key = getLibrisKey( $self );

    if ( !$libris_key ) {
        $errormessage = "API-nyckel saknas för sigel";
    } else {

        # Build the url
        my $url = "$protocol://$host/$string/$branch_fixed/outgoing?start_date=$start" . "&end_date=$end";

        # Fetch the actual data from the query
        my $request = HTTP::Request->new("GET" => $url);

        $request->header( 'api-key' => $libris_key );

        my $response = $ua->request($request);

        $jsonString = $response->content;

        $decoded = decode_json($jsonString);

        %lf_numbers = map { $_->{lf_number} } @{ $decoded->{ill_requests} };

        %users = map { $_->{user} } @{ $decoded->{ill_requests} };

        %titles = map { $_->{title} } @{ $decoded->{ill_requests} };

        %bib_ids = map { $_->{bib_id} } @{ $decoded->{ill_requests} };
    }

    $template->param(
        jsonString       => $jsonString,
        decoded          => $decoded,
        titles           => %titles,
        users            => %users,
        lf_numbers       => %lf_numbers,
        bib_ids          => %bib_ids,
        errormessage     => $errormessage,
        plugin_dir       => $self->bundle_path,
    );

    output_html_with_http_headers $query, $cookie, $template->output;


}


sub librisill_request {
    my ( $self, @args ) = @_;

    my $query = CGI->new;

    my ( $template, $loggedinuser, $cookie, $flags ) = get_template_and_user(
        {
            template_name   => $self->mbf_path("librisill-request.tt"),
            query           => $query,
            type            => "intranet",
            flagsrequired   => { circulate => "circulate_remaining_permissions" },
        }
    );

    my $branch;
    if (C4::Context->userenv) {
        $branch = C4::Context->userenv->{'branch'};
    }

    # Search query
    my $branch_fixed = join '', map { ucfirst lc $_ } split /(\s+)/, $branch;
    my $lfnumber = $query->param('lfnumber');

    my $ua = new LWP::UserAgent;
    $ua->agent("Perl API Client/1.0");

    # Setup variables
    my $string="librisfjarrlan/api/illrequests";
    my $host="iller.libris.kb.se";
    my $protocol="https";
    my $libris_key = getLibrisKey( $self ); # $libris_keys->{data}[0]{$branch_fixed};


    # Build the url
    my $url = "$protocol://$host/$string/$branch_fixed/$lfnumber";

    # Fetch the actual data from the query
    my $request = HTTP::Request->new("GET" => $url);

    $request->header( 'api-key' => $libris_key );

    my $response = $ua->request($request);

    my $jsonString = $response->content;

    my $decoded = decode_json($jsonString);

    my $user_id = $decoded->{ill_requests}->[0]->{user_id};

    my $patron = Koha::Patrons->find( { cardnumber => $user_id } );

    my $patron_id = length($patron);

    my $patron_name = length($patron);

    if ($patron ne undef) {
    $patron_id = $patron->borrowernumber;
    $patron_name = $patron->surname . ", " . $patron->firstname;
    } else {
    $patron_id = "";
    $patron_name = "";
    };

    my @library_arr = map { $_->{library_code} } @{ $decoded->{ill_requests}->[0]->{recipients} };
    foreach (@library_arr) {
        $_ = "+$_";
    }
    my $library_codes = scalar "@library_arr";

    my %ill_hash = (
        author => $decoded->{ill_requests}->[0]->{author},
        title =>  $decoded->{ill_requests}->[0]->{title},
        imprint => $decoded->{ill_requests}->[0]->{imprint},
        bib_id => $decoded->{ill_requests}->[0]->{bib_id},
        isbn_issn => $decoded->{ill_requests}->[0]->{isbn_issn},
        user => $decoded->{ill_requests}->[0]->{user},
        user_id => $decoded->{ill_requests}->[0]->{user_id},
        active_library => $decoded->{ill_requests}->[0]->{active_library},
        lf_number => $decoded->{ill_requests}->[0]->{lf_number},
        library_codes => $library_codes,
        patron_id => $patron_id,
        patron_name => $patron_name,
    );

    my $ill_json = encode_json \%ill_hash;


    $template->param(
        jsonString                     => $jsonString,
        decoded	                       => $decoded,
        patron                         => $patron,
        library_codes                  => $library_codes,
        ill_JSON			           => $ill_json,
        plugin_dir                     => $self->bundle_path,
    );

    output_html_with_http_headers $query, $cookie, $template->output;

}



sub librisill_incomings {
    my ( $self, @args ) = @_;

    my $query = new CGI;

    my ( $template, $loggedinuser, $cookie, $flags ) = get_template_and_user(
        {
            template_name   => $self->mbf_path("librisill-incomings.tt"),
            query           => $query,
            type            => "intranet",            
            flagsrequired   => { catalogue => 1, },
        }
    );

    my $branch;
    if (C4::Context->userenv) {
        $branch = C4::Context->userenv->{'branch'};
    }
    my $branch_fixed = join '', map { ucfirst lc $_ } split /(\s+)/, $branch;

    my $errormessage;

    my $time = time();

    my $end_raw = strftime "%F", localtime($time);
    my $start_raw = strftime "%F", localtime($time-30*24*60*60);
    
    my $start = substr($start_raw, 0, 5) . (sprintf "%d" , substr($start_raw, 5, 2)) . "-" . sprintf "%d" , substr($start_raw, 8, 2);
    my $end = substr($end_raw, 0, 5) . (sprintf "%d" , substr($end_raw, 5, 2)) . "-" . sprintf "%d" , substr($end_raw, 8, 2);
    

    # Search query
    my $sigil = $branch_fixed;
    my $archive = $query->param('archive');
    my $action = $query->param('action');
    my $response_id = $query->param('response_id');
    my $added_response = $query->param('added_response');
    my $may_reserve = $query->param('may_reserve');
    my $order_id = $query->param('order_id');
    my $timestamp = $query->param('last_modified');

    my $url;
    my $fragment;
    my $extra_content;
    my $request;
    my $orig_data;
    my $update_data;
    my $decoded;
    my @ill_libraries;    
    my @ill_sigels;
    my $ill_requests;

    my $libris_key = getLibrisKey( $self );

    if ( !$libris_key ) {
        $errormessage = "API-nyckel saknas för sigel";
    } else {

        warn "Archive? : " . $archive;

        if ($action) {

            $extra_content = "&may_reserve=$may_reserve&response_id=$response_id&added_response=$added_response";
        
        } elsif ($archive) {

            $fragment = "illrequests/$sigil/incoming_archive?start_date=$start&end_date=$end";

        } else {

            $fragment = "illrequests/$sigil/incoming";

        }

        # Fetch the actual data from the query
        if ( $action ) {
            
            $update_data = _update_libris( $sigil, $libris_key, $order_id, $action, $extra_content);
            $fragment = "illrequests/$sigil/incoming";
            $orig_data = _get_data_from_libris( $sigil, $libris_key, $fragment);

        } else {
            
            $orig_data = _get_data_from_libris( $sigil, $libris_key, $fragment);

        }

        $decoded = $orig_data;

        $ill_requests = $decoded->{'ill_requests'};

        if ( $decoded->{'count'} > 0 ) {

            $ill_requests = $decoded->{'ill_requests'};

            for my $ill ( @$ill_requests ) {
                push (@ill_sigels, $ill->{'requesting_library'}) unless $ill->{'requesting_library'} ~~ @ill_sigels;
            }

            my $sigel = join("," , @ill_sigels);

            my $libdataJSON = getlibdata( $self, $sigel);
            my $libdata = decode_json( $libdataJSON );
            my $lib = $libdata->{'libraries'};

            for my $li ( @$lib ) {

                my $searchstr = $li->{'name'};
                $searchstr =~ s/ /+/g;

                push (@ill_libraries, {
                    sigel             => $li->{'library_code'},
                    libraryname       => $li->{'name'},
                    library_id        => $li->{'library_id'},
                    searchstr         => $searchstr,
                });
            }
        }
        
    }

    $template->param(    
        decoded                        => $decoded,
        action                         => $action,
        archive                        => $archive,
        sigil                          => $sigil,
        ill_libraries                  => \@ill_libraries,
        errormessage                   => $errormessage,
        plugin_dir                     => $self->bundle_path,
    );

    output_html_with_http_headers $query, $cookie, $template->output;
 
}


sub _get_data_from_libris {
    my ( $sigil, $libris_key, $fragment ) = @_;

    my $base_url  = 'https://iller.libris.kb.se/librisfjarrlan/api';
    
    # Create a user agent object
    my $ua = LWP::UserAgent->new;
    $ua->agent("Koha ILL");

    # Replace placeholders in the fragment
    $fragment =~ s/__sigil__/$sigil/g;

    # Create a request
    my $url = "$base_url/$fragment";
    warn "Requesting $url";
    my $request = HTTP::Request->new( GET => $url );
    $request->header( 'api-key' => $libris_key );

    # Pass request to the user agent and get a response back
    my $res = $ua->request($request);

    my $json;
    # Check the outcome of the response
    if ($res->is_success) {
        $json = $res->content;
        warn "JSON:" . $json;
    } else {
        warn $res->status_line;
    }

    unless ( $json ) {
        warn "No JSON!";
        # exit;
    }

    my $data = decode_json( $json );
    if ( $data->{'count'} == 0 ) {
        warn "No data!";
        # exit;
    }

    return $data;

}


sub _update_libris {
    my ( $sigil, $libris_key, $order_id, $action, $extra_content ) = @_;

    # my $orderid = $request->orderid;
    warn "*** orderid: $order_id";

    # Figure out the sigil that the current request is connected to
    # my $sigil = $sigil;
    warn "Handling request on behalf of $sigil";
    
    # my $status = $request->status;
    # $status =~ m/(.*?)_.*/g;
    my $direction = $1;

    my $orig_data = _get_data_from_libris( $sigil, $libris_key, "illrequests/$sigil/$order_id" );

    # Pick out the timestamp
    my $newtimestamp = $orig_data->{'ill_requests'}->[0]->{'last_modified'};
    warn "*** timestamp: $newtimestamp";

    # The extra-content being sent

    warn "*** extra_content: $extra_content";
    
    ## Make the call back to Libris, to change the status

    # Create a user agent object
    my $ua = LWP::UserAgent->new;
    $ua->agent("Koha ILL");

    # Create a request
    my $url = "https://iller.libris.kb.se/librisfjarrlan/api/illrequests/$sigil/$order_id";
    warn "POSTing to $url";
    my $req = HTTP::Request->new( 'POST', $url );
    warn "*** libris_key: " . $libris_key;
    $req->header( 'api-key' => $libris_key );
    $req->header( 'Content-Type' => 'application/x-www-form-urlencoded' );
    $req->content( "action=$action&timestamp=$newtimestamp$extra_content" );

    # Pass request to the user agent and get a response back
    my $res = $ua->request($req);

    # Check the outcome of the response
    if ( $res->is_success ) { 

        my $json = $res->content;
        my $new_data = decode_json( $json );

        warn "*** Update action: " . $new_data->{'update_action'};
        warn "*** Update success: " . $new_data->{'update_success'};
        warn "*** Update message: " . $new_data->{'update_message'};
        warn "*** Last modified: " . $new_data->{'ill_requests'}->[0]->{'last_modified'};
        warn "*** Status: " . $new_data->{'ill_requests'}->[0]->{'status'};

    } else {

        warn "--- ERROR ---";

    }

    return $res;

}


sub getlibdata {

    my ( $self, $sigel ) = @_;

    my $branch;
    if (C4::Context->userenv) {
        $branch = C4::Context->userenv->{'branch'};
    }
    my $branch_fixed = join '', map { ucfirst lc $_ } split /(\s+)/, $branch;

    my $query = new CGI;

    if ( $query->param('sigel') ) {
        $sigel = $branch_fixed . ',' . $query->param('sigel');
    } else {
        warn "Ingen sigel i query";
    }

    my $ua = new LWP::UserAgent;
    $ua->agent("Koha ILL");

    # Setup variables
    my $string = "librisfjarrlan/api/libraries";
    my $host = "iller.libris.kb.se";
    my $protocol = "https";
    my $libris_key = getLibrisKey( $self ); 

    # Build the url
    my $url = "$protocol://$host/$string/$branch_fixed/$sigel";

    # Fetch the actual data from the query
    my $request = HTTP::Request->new("GET" => $url);

    $request->header( 'api-key' => $libris_key );
    #$request->content_type('application/json');

    my $response = $ua->request($request);

    my $jsonString = $response->content;

    if ( $query->param('sigel') ) {
        my $cgi = CGI->new;
        print $cgi->header(-type => "application/json", -charset => "utf-8");
        print $jsonString;
    } else {
        return $jsonString;
    }

}


sub import_ill {
    my ( $self, @args ) = @_;

    my $homebranch;
    if (C4::Context->userenv) {
        $homebranch = C4::Context->userenv->{'branch'};
    }

    my $query = CGI->new;    

    my $bib_id = $query->param('bib_id');
    my $borrowernumber = $query->param('borrowernumber');
    my $ill_id = $query->param('ill_id');

    my $ill_itemtype = $self->retrieve_data('itemtype');
    my $ill_callnumber = "FJÄRRLÅN";
    my $ill_ccode = $self->retrieve_data('ccode');
    my $ill_location = $self->retrieve_data('loc');
    my $ill_notforloan = $self->retrieve_data('notforloan');

    my $record = get_record_from_libris( $bib_id );

    $record = _append_to_field( $record, '245', 'a', 'FJÄRRLÅN' );

    my $ill_marc = MARC::Field->new(
        '887',' ',' ',
        a => $ill_id,
    );
    $record->insert_fields_ordered( $ill_marc );

    my ( $biblionumber, $biblioitemnumber, $itemnumber );

    ( $biblionumber, $biblioitemnumber ) = AddBiblio( $record, '' );
        
    my $item_hash = {
        'biblionumber'   => $biblionumber,
        'biblioitemnumber' => $biblioitemnumber,
        'homebranch'     => $homebranch,
        'holdingbranch'  => $homebranch,
        'itype'          => $ill_itemtype,
        'itemcallnumber' => $ill_callnumber,
        'notforloan'     => $ill_notforloan,
        'ccode'          => $ill_ccode,
        'location'       => $ill_location,
        'itemnotes_nonpublic' => $ill_id,
    };

    my $item = Koha::Item->new( $item_hash );
    
    my $error = 0;

    if ( defined $item ) {
        $item->store;
        $itemnumber = $item->itemnumber;
    } else {
        $error = 1;
    }

    my %import = (
        itemnumber => $itemnumber,        
        error => $error,
    );

    my $cgi = CGI->new;

    if ( $borrowernumber ) {
        AddReserve(
            {
                branchcode       => $homebranch,
                borrowernumber   => $borrowernumber,
                biblionumber     => $biblionumber,
                priority         => undef,
                reservation_date => undef,
                expiration_date  => undef,
                notes            => undef,
                title            => undef,
                itemnumber       => $itemnumber,
                found            => undef,
                itemtype         => $ill_itemtype,
                non_priority     => undef,
            }
        );
    } else {
        $import{'no_borrower'} = 1;
    }

    my $importJSON = encode_json( \%import );

    warn "ImportJSON: " . $importJSON;

    print $cgi->header(-type => "application/json", -charset => "utf-8");

    print $importJSON;

}


sub get_record_from_libris {

    my ( $libris_id ) = @_; 

    my $xml = get("http://api.libris.kb.se/sru/libris?version=1.1&operation=searchRetrieve&query=rec.recordIdentifier=$libris_id");
    return unless $xml;
    $xml =~ m/(<record .*>.*?<\/record>)<\/recordData>/;
    my $record_xml = $1;
    return unless $record_xml;
    my $record = MARC::Record->new_from_xml( $record_xml, 'UTF-8', 'MARC21' );
    return unless $record;

    $record->encoding( 'UTF-8' );

    # Remove unnecessary fields
    foreach my $tag ( qw( 841 852 887 950 955 ) ) {
       $record->delete_fields( $record->field( $tag ) );
    }

    # say $record->as_formatted();

    return $record;

}


sub _append_to_field {

    my ( $record, $field, $subfield, $string ) = @_;

    my $this_field = $record->field( $field );
    my $old_text = $this_field->subfield( $subfield );
    my $new_text = "[$string] $old_text";

    $this_field->update( $subfield => $new_text );

    return $record;

}

1;

