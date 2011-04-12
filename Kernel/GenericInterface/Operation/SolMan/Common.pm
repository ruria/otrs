# --
# Kernel/GenericInterface/Operation/SolMan/Common.pm - SolMan common operation functions
# Copyright (C) 2001-2011 OTRS AG, http://otrs.org/
# --
# $Id: Common.pm,v 1.3 2011-04-12 14:08:55 mg Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::GenericInterface::Operation::SolMan::Common;

use strict;
use warnings;

use MIME::Base64();
use Kernel::System::VariableCheck qw(IsHashRefWithData IsStringWithData);

use Kernel::System::Ticket;
use Kernel::System::CustomerUser;
use Kernel::System::User;

use vars qw(@ISA $VERSION);
$VERSION = qw($Revision: 1.3 $) [1];

=head1 NAME

Kernel::GenericInterface::Operation::SolMan::Common - common operation functions

=head1 SYNOPSIS

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object

    use Kernel::Config;
    use Kernel::System::Encode;
    use Kernel::System::Log;
    use Kernel::System::Time;
    use Kernel::System::Main;
    use Kernel::System::DB;
    use Kernel::GenericInterface::Operation::SolMan::Common;

    my $ConfigObject = Kernel::Config->new();
    my $EncodeObject = Kernel::System::Encode->new(
        ConfigObject => $ConfigObject,
    );
    my $LogObject = Kernel::System::Log->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
    );
    my $TimeObject = Kernel::System::Time->new(
        ConfigObject => $ConfigObject,
        LogObject    => $LogObject,
    );
    my $MainObject = Kernel::System::Main->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
        LogObject    => $LogObject,
    );
    my $DBObject = Kernel::System::DB->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
        LogObject    => $LogObject,
        MainObject   => $MainObject,
    );
    my $SolManCommonObject = Kernel::GenericInterface::Operation::SolMan::Common->new(
        ConfigObject       => $ConfigObject,
        LogObject          => $LogObject,
        DBObject           => $DBObject,
        MainObject         => $MainObject,
        TimeObject         => $TimeObject,
        EncodeObject       => $EncodeObject,
    );

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for my $Needed (
        qw( DebuggerObject MainObject TimeObject ConfigObject LogObject DBObject EncodeObject WebserviceID)
        )
    {

        if ( !$Param{$Needed} ) {
            return {
                Success      => 0,
                ErrorMessage => "Got no $Needed!"
            };
        }

        $Self->{$Needed} = $Param{$Needed};
    }

    $Self->{TicketObject}       = Kernel::System::Ticket->new( %{$Self} );
    $Self->{CustomerUserObject} = Kernel::System::CustomerUser->new( %{$Self} );
    $Self->{UserObject}         = Kernel::System::User->new( %{$Self} );

    return $Self;
}

=item TicketSync()

Create/Update a local ticket.

    my $Result = $OperationObject->TicketSync(
        Operation => 'ReplicateIncident', # ProcessIncident, ReplicateIncident, AddInfo or CloseIncident
        Data => {
            IctAdditionalInfos  => {},
            IctAttachments      => {},
            IctHead             => {},
            IctId               => '',  # type="n0:char32"
            IctPersons          => {},
            IctSapNotes         => {},
            IctSolutions        => {},
            IctStatements       => {},
            IctTimestamp        => '',  # type="n0:decimal15.0"
            IctUrls             => {},
        },
    );

    $Result = {
        Success         => 1,                       # 0 or 1
        ErrorMessage    => '',                      # in case of error
        Data            => {                        # result data payload after Operation
            PrdIctId   => '2011032400001',          # Incident number in the provider (help desk system) / type="n0:char32"
            PersonMaps => {                         # Mapping of person IDs / tns:IctPersonMaps
                Item => {
                    PersonId    => '0001',
                    PersonIdExt => '5050',
                },
            },
            Errors => {                         # should not return errors
                item => {
                    ErrorCode => '01'
                    Val1      =>  'Error Description',
                    Val2      =>  'Error Detail 1',
                    Val3      =>  'Error Detail 2',
                    Val4      =>  'Error Detail 3',

                },
            },
        },
    };

=cut

sub TicketSync {
    my ( $Self, %Param ) = @_;

    if ( !IsStringWithData( $Param{Operation} ) ) {
        return $Self->{DebuggerObject}->Error( Summary => 'Got no Data' );
    }

    # we need Data
    if ( !IsHashRefWithData( $Param{Data} ) ) {
        return $Self->{DebuggerObject}->Error( Summary => 'Got no Data' );
    }

    # check needed data
    for my $Key (qw(IctHead)) {
        if ( !IsHashRefWithData( $Param{Data}->{$Key} ) ) {
            return $Self->{DebuggerObject}->Error( Summary => "Got no Data->$Key" );
        }
    }

    for my $Key (qw(IncidentGuid)) {
        if ( !IsStringWithData( $Param{Data}->{IctHead}->{$Key} ) ) {
            return $Self->{DebuggerObject}->Error( Summary => "Got no Data->IctHead->$Key" );
        }
    }

    #    for my $Key (qw(IctTimestamp)) {
    #        if ( !IsStringWithData( $Param{Data}->{$Key} ) ) {
    #            return $Self->{DebuggerObject}->Error( Summary => "Got no Data->$Key" );
    #        }
    #    }

    my $TicketID;

    my $IncidentGuidTicketFlagName = "GI_$Self->{WebserviceID}_SolMan_IncidentGuid";

    my %PrioritySolMan2OTRS = (
        1 => '5 very high',
        2 => '4 high',
        3 => '3 normal',
        4 => '2 low',
    );

    my $TargetPriority = $PrioritySolMan2OTRS{ $Param{Data}->{IctHead}->{Priority} || 3 };

    if ( $Param{Operation} eq 'ProcessIncident' || $Param{Operation} eq 'ReplicateIncident' ) {

        # create ticket
        $TicketID = $Self->{TicketObject}->TicketCreate(
            Title        => $Param{Data}->{IctHead}->{ShortDescription},
            Queue        => 'Raw',
            Lock         => 'unlock',
            Priority     => $TargetPriority,
            State        => 'closed successful',
            CustomerNo   => $Param{Data}->{IctHead}->{ReporterId},
            CustomerUser => $Param{Data}->{IctHead}->{ReporterId},
            OwnerID      => 1,
            UserID       => 1,
        );
        if ( !$TicketID ) {
            return $Self->{DebuggerObject}->Error(
                Summary => $Self->{LogObject}->GetLogEntry(
                    Type => 'error',
                    What => 'message',
                ),
            );
        }

        my $Success = $Self->{TicketObject}->TicketFlagSet(
            TicketID => $TicketID,
            Key      => $IncidentGuidTicketFlagName,
            Value    => $Param{Data}->{IctHead}->{IncidentGuid},
            UserID   => 1,
        );
    }
    else {

        # find ticket based on IncidentGuid
        my @Tickets = $Self->{TicketObject}->TicketSearch(
            Result     => 'ARRAY',
            Limit      => 2,
            TicketFlag => {
                $IncidentGuidTicketFlagName => $Param{Data}->{IctHead}->{IncidentGuid},
            },
            UserID     => 1,
            Permission => 'rw',
        );

        if ( scalar @Tickets != 1 ) {
            return $Self->{DebuggerObject}->Error(
                Summary =>
                    "Could not find ticket for IncidentGuid $Param{Data}->{IctHead}->{IncidentGuid}"
            );
        }

        $TicketID = $Tickets[0];

        # update fields if neccessary
        if ( $Param{Data}->{IctHead}->{ShortDescription} ) {
            my $Success = $Self->{TicketObject}->TicketTitleUpdate(
                Title    => $Param{Data}->{IctHead}->{ShortDescription},
                TicketID => $TicketID,
                UserID   => 1,
            );

            if ( !$Success ) {
                return $Self->{DebuggerObject}->Error(
                    Summary => "Could not update ticket title!",
                );
            }
        }

        if ( $Param{Data}->{IctHead}->{Priority} ) {
            my $Success = $Self->{TicketObject}->TicketPrioritySet(
                TicketID => $TicketID,
                Priority => $TargetPriority,
                UserID   => 1,
            );

            if ( !$Success ) {
                return $Self->{DebuggerObject}->Error(
                    Summary => "Could not update ticket priority!",
                );
            }
        }

    }

    # create article
    if ( $Param{Data}->{IctStatements} && $Param{Data}->{IctStatements}->{item} ) {
        my $ArticleID;
        for my $Items ( @{ $Param{Data}->{IctStatements}->{item} } ) {
            next if !$Items;
            next if ref $Items ne 'HASH';
            next if !$Items->{Texts};
            next if ref $Items->{Texts} ne 'HASH';
            next if !$Items->{Texts}->{item};
            next if ref $Items->{Texts}->{item} ne 'ARRAY';

            # construct the text body from multiple item nodes
            my ( $Year, $Month, $Day, $Hour, $Minute, $Second ) = $Items->{Timestamp}
                =~ m/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/smx;
            my $Body = "($Items->{PersonId}) $Day.$Month.$Year $Hour:$Minute:$Second\n";
            $Body .= join "\n", @{ $Items->{Texts}->{item} };

            my $ArticleIDLocal = $Self->{TicketObject}->ArticleCreate(
                TicketID       => $TicketID,
                ArticleType    => 'note-internal',
                SenderType     => 'agent',
                From           => 'Some Agent <email@example.com>',
                Subject        => "IctStatement from SolMan",
                Body           => $Body,
                Charset        => 'utf-8',
                MimeType       => 'text/plain',
                HistoryType    => 'AddNote',
                HistoryComment => 'Update from SolMan',
                UserID         => 1,
            );
            if ( !$ArticleIDLocal ) {
                return $Self->{DebuggerObject}->Error(
                    Summary => $Self->{LogObject}->GetLogEntry(
                        Type => 'error',
                        What => 'message',
                    ),
                );
            }
            $ArticleID = $ArticleIDLocal;
        }

        # create attachments
        if ( $Param{Data}->{IctAttachments} && $Param{Data}->{IctAttachments}->{item} ) {
            for my $Attachment ( @{ $Param{Data}->{IctAttachments}->{item} } ) {
                my $Success = $Self->{TicketObject}->ArticleWriteAttachment(
                    Content     => MIME::Base64::decode_base64( $Attachment->{Data} ),
                    Filename    => $Attachment->{Filename},
                    ContentType => $Attachment->{MimeType},
                    ArticleID   => $ArticleID,
                    UserID      => 1,
                );
            }
        }
    }

    my %Ticket = $Self->{TicketObject}->TicketGet(
        TicketID => $TicketID,
        UserID   => 1,
    );

    # copy data
    my $ReturnData = {
        Errors   => '',
        PrdIctId => $Ticket{TicketNumber},
    };

    # return result
    return {
        Success => 1,
        Data    => $ReturnData,
    };
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

=head1 VERSION

$Revision: 1.3 $ $Date: 2011-04-12 14:08:55 $

=cut
