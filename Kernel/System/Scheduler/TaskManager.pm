# --
# Kernel/System/Scheduler/TaskManager.pm - Scheduler TaskManager backend
# Copyright (C) 2001-2011 OTRS AG, http://otrs.org/
# --
# $Id: TaskManager.pm,v 1.1 2011-02-10 16:28:38 martin Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Scheduler::TaskManager;

use strict;
use warnings;

use YAML;

use vars qw(@ISA $VERSION);
$VERSION = qw($Revision: 1.1 $) [1];

=head1 NAME

Kernel::System::TaskManager

=head1 SYNOPSIS

TaskManager backend for Scheduler

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object

    use Kernel::Config;
    use Kernel::System::Encode;
    use Kernel::System::Log;
    use Kernel::System::Main;
    use Kernel::System::DB;
    use Kernel::System::Scheduler::TaskManager;

    my $ConfigObject = Kernel::Config->new();
    my $EncodeObject = Kernel::System::Encode->new(
        ConfigObject => $ConfigObject,
    );
    my $LogObject = Kernel::System::Log->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
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
    my $TaskManagerObject = Kernel::System::Scheduler::TaskManager->new(
        ConfigObject => $ConfigObject,
        LogObject    => $LogObject,
        DBObject     => $DBObject,
        MainObject   => $MainObject,
        EncodeObject => $EncodeObject,
    );

=cut

sub new {
    my ( $TaskManager, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $TaskManager );

    # check needed objects
    for my $Object (qw(DBObject ConfigObject LogObject MainObject EncodeObject)) {
        $Self->{$Object} = $Param{$Object} || die "Got no $Object!";
    }

    return $Self;
}

=item TaskAdd()

add new Tasks

    my $ID = $TaskObject->TaskAdd(
        Data => {
            ...
        },
        UserID  => 123,
    );

=cut

sub TaskAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Key (qw(Data UserID)) {
        if ( !$Param{$Key} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $Key!" );
            return;
        }
    }

    # dump config as string
    my $Data = YAML::Dump( $Param{Data} );

    # sql
    return if !$Self->{DBObject}->Do(
        SQL =>
            'INSERT INTO scheduler_task_list (task_data, create_time, create_by)'
            . ' VALUES (?, current_timestamp, ?)',
        Bind => [
            \$Data, \$Param{UserID}, \$Param{UserID},
        ],
    );

    return if !$Self->{DBObject}->Prepare(
        SQL   => 'SELECT id FROM scheduler_task_list WHERE task_data = ? ORDER BY create_time DESC',
        Bind  => [ \$Data ],
        Limit => 1,
    );
    my $ID;
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
        $ID = $Row[0];
    }
    return $ID;
}

=item TaskGet()

get Tasks attributes

    my %Task = $TaskObject->TaskGet(
        ID => 123,
    );

Returns:

    %Task = (
        Data         => $DataRef,
        CreateTime   => '2011-02-08 15:08:00',
    );

=cut

sub TaskGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{ID} ) {
        $Self->{LogObject}->Log( Priority => 'error', Message => 'Need ID!' );
        return;
    }

    # sql
    return if !$Self->{DBObject}->Prepare(
        SQL  => 'SELECT task_data, create_time FROM scheduler_task_list WHERE id = ?',
        Bind => [ \$Param{ID} ],
    );
    my %Data;
    while ( my @Data = $Self->{DBObject}->FetchrowArray() ) {
        my $DataParam = YAML::Load( $Data[0] );

        %Data = (
            ID         => $Param{ID},
            Data       => $DataParam,
            CreateTime => $Data[1],
        );
    }
    return %Data;
}

=item TaskDelete()

delete Task

    $TaskObject->TaskDelete(
        ID     => 123,
        UserID => 123,
    );

=cut

sub TaskDelete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Key (qw(ID UserID)) {
        if ( !$Param{$Key} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $Key!" );
            return;
        }
    }

    # sql
    return if !$Self->{DBObject}->Do(
        SQL  => 'DELETE FROM scheduler_task_list WHERE id = ?',
        Bind => [ \$Param{ID} ],
    );
    return 1;
}

=item TaskList()

get Task list for a Scheduler

    my @List = $TaskObject->TaskList();

=cut

sub TaskList {
    my ( $Self, %Param ) = @_;

    return if !$Self->{DBObject}->Prepare(
        SQL => 'SELECT id FROM scheduler_task_list',
    );

    my @List;
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
        push @List, $Row[0];
    }
    return @List;
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

$Revision: 1.1 $ $Date: 2011-02-10 16:28:38 $

=cut
