#For static stats. Generate stats regarding CMDB Config Item which are connected to the ticket.
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --
###OTRS 6 API REFERENCE: https://doc.otrs.com/doc/api/otrs/6.0/Perl/index.html

package Kernel::System::Stats::Static::CMDBRelatedTicket;
## nofilter(TidyAll::Plugin::OTRS::Perl::Time)

use strict;
use warnings;
use List::Util qw( first );

#use Kernel::System::VariableCheck qw(:all);
#use Kernel::Language qw(Translatable);

our @ObjectDependencies = (
	'Kernel::Config',
    'Kernel::Language',
    'Kernel::System::DB',
);

sub new {
    my ( $Type, %Param ) = @_;

    ### allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );
	
	
	return $Self;
}

sub GetObjectBehaviours {
    my ( $Self, %Param ) = @_;

    my %Behaviours = (
        ProvidesDashboardWidget => 0,
    );

    return %Behaviours;
}

sub Param {
    my $Self = shift;

    my @Params = ();
	
	my $GeneralCatalogObject = $Kernel::OM->Get('Kernel::System::GeneralCatalog');
	my $ClassList = $Kernel::OM->Get('Kernel::System::GeneralCatalog')->ItemList(
        Class => 'ITSM::ConfigItem::Class',
    );
	
	# Get current time.
    my $DateTimeObject = $Kernel::OM->Create(
        'Kernel::System::DateTime',
    );
    my $DateTimeSettings = $DateTimeObject->Get();
	
	# get current year
    my $Y = sprintf( "%02d", $DateTimeSettings->{Year} );
	# get one month before
    my $PM = sprintf( "%02d", $DateTimeSettings->{Month} - 1 );
	# get current month
	my $M = sprintf( "%02d", $DateTimeSettings->{Month} );
	
	# Create possible time selections.
    my %Year  = map { $_ => $_ } ( $Y - 10 .. $Y + 1 );
    my %Month = map { sprintf( "%02d", $_ ) => sprintf( "%02d", $_ ) } ( 1 .. 12 );
	
	push @Params, {
        Frontend   => 'Class',
        Name       => 'Class',
        Multiple   => 0,
        Size       => 1,
        SelectedID => 0,
        Data       => {
            %{$ClassList}, 
        },
    };
	
	push @Params, {
        Frontend   => 'Incident Reported (From Month)',
        Name       => 'FromMonth',
        Multiple   => 0,
        Size       => 0,
        SelectedID => $PM,
        Data       => {
            %Month, 
        },
    };
	
	push @Params, {
        Frontend   => 'Incident Reported (To Month)',
        Name       => 'ToMonth',
        Multiple   => 0,
        Size       => 0,
        SelectedID => $M,
        Data       => {
            %Month, 
        },
    };
	
	push @Params, {
        Frontend   => 'Incident Reported (For Year)',
        Name       => 'ForYear',
        Multiple   => 0,
        Size       => 0,
        SelectedID => $Y,
        Data       => {
            %Year, 
        },
    };
	
    return @Params;
		
}

sub Run {
   my ( $Self, %Param ) = @_;

	my $ClassID =  $Param{Class};
	my $FromMonth =  $Param{FromMonth};
	my $ToMonth =  $Param{ToMonth};
	my $ForYear =  $Param{ForYear};
	
	# validate date selection
    if ( $FromMonth >  $ToMonth) 
	{
		
		local $Kernel::OM = Kernel::System::ObjectManager->new(
        'Kernel::System::Log' => {
            LogPrefix => 'CMDB Statistic',  # not required, but highly recommend
        },
		);
		
		$Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'From Month must be lower or same than To Month!',
        );
        return;
		
    }
	
	#building end month date
	my $EndDateVariable = $Kernel::OM->Create(
        'Kernel::System::DateTime',
        ObjectParams => {
            Year     => $ForYear,
            Month    => $ToMonth,
            Day      => 1,
            Hour     => 0,                     # optional, defaults to 0
            Minute   => 0,                     # optional, defaults to 0
            Second   => 0,                     # optional, defaults to 0
        }
    );
	
	my $LastDayOfMonth = $EndDateVariable->LastDayOfMonthGet();
	
	my $TicketCreateTimeNewerDate = "$ForYear-$FromMonth-01 00:00:01";
	my $TicketCreateTimeOlderDate = "$ForYear-$ToMonth-$LastDayOfMonth->{Day} 23:59:59";
	
	my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
	
	##search ticket based on date selection
	my @TicketIDs = $TicketObject->TicketSearch(
		Result => 'ARRAY',
		# tickets with create time after ... (ticket newer than this date) (optional)
        TicketCreateTimeNewerDate => "$ForYear-$FromMonth-01 00:00:01",
        # tickets with created time before ... (ticket older than this date) (optional)
        TicketCreateTimeOlderDate => "$ForYear-$ToMonth-$LastDayOfMonth->{Day} 23:59:59",
		UserID     => 1,
	);
	
	return if !@TicketIDs;
	
	my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
	my $random_number = int(rand(100));
	my $DBTable1 = "configitem_own_data_$random_number";
	my $SQLDROP1 = "DROP TEMPORARY TABLE IF EXISTS $DBTable1";
	$DBObject->Do( SQL => $SQLDROP1);
	
	my $SQLTempTable1  = "CREATE TEMPORARY TABLE $DBTable1 (
						ticket_number VARCHAR(50),
						ticket_title VARCHAR(255),
						ticket_create_time DATETIME,
						ci_class VARCHAR(255),
						ci_number VARCHAR(50),
						ci_name VARCHAR(255)
						)";
	
	
	$DBObject->Do( SQL => $SQLTempTable1);
	
	my $LinkObject = $Kernel::OM->Get('Kernel::System::LinkObject');
	#my @Data;
	
    foreach my $TicketID (@TicketIDs)
    {
        my %LinkKeyList = $LinkObject->LinkKeyListWithData(
        Object1    => 'Ticket',
        Key1       => $TicketID,
        Object2   => 'ITSMConfigItem',         # (optional)
        State     => 'Valid',
        UserID    => 1,
        );
        
        next if !%LinkKeyList;
		
		my %Ticket = $TicketObject->TicketGet(
        TicketID      => $TicketID,
        UserID        => 1,
		);
       
        foreach my $SubItemID (values %LinkKeyList) 
        {
            next if $ClassID ne $SubItemID->{ClassID};
			#push @Data, [ $Ticket{TicketNumber}, $Ticket{Title}, $Ticket{Created}, $SubItemID->{Class}, $SubItemID->{Number}, $SubItemID->{Name} ];
			
			##Put the result from api to db tmp table
			my $Success = $DBObject->Do(
				SQL => "INSERT INTO $DBTable1 "
				. "(ticket_number, ticket_title, ticket_create_time, ci_class, ci_number, ci_name) "
					. "VALUES (?, ?, ?, ?, ?, ?)",
				Bind => [ \$Ticket{TicketNumber}, \$Ticket{Title}, \$Ticket{Created}, \$SubItemID->{Class}, \$SubItemID->{Number}, \$SubItemID->{Name} ],
			);
			
			return if !$Success;	
			
        }
        
         
    }
	
	my @Stats1 = ();
	my $Title = "CMDB Related Ticket From $ForYear-$FromMonth To $ForYear-$ToMonth";
	
	###MYSQL select all..
	my $SQL1 = "SELECT * FROM $DBTable1	ORDER BY ci_number";
	$DBObject->Prepare( SQL => $SQL1);
	my @HeadData1 = $DBObject->GetColumnNames();
	$_ = uc for @HeadData1;

	my $count1 = 0;
    while ( my @Row1 = $DBObject->FetchrowArray() ) {
		push @Stats1, \@Row1;
		$count1++;
	
	}
	
	unless ($count1) {
	undef @HeadData1;
	my @NODATA = "Sorry 0 Result" ;
	push @Stats1, \@NODATA;
	}
	####################
	
	###MYSQL get count and percent, etc..
	my @Stats2 = ();
	my $SQL2 = "
	SELECT ci_name AS 'CI_NAME',
	COUNT(ci_number) AS 'FREQUENCY',
	CONCAT(FORMAT(COUNT(ci_number) / $count1 * 100,2),'%') AS 'PERCENTAGE'
	FROM $DBTable1 
	GROUP BY ci_number
	";

	
	
	$DBObject->Prepare( SQL => $SQL2);
	my @HeadData2 = $DBObject->GetColumnNames();
	$_ = uc for @HeadData2;
	push @Stats2, ['EFFECTED ITEM FREQUENCY'];
	push @Stats2, [@HeadData2];
	
	my $count2 = 0;
    while ( my @Row2 = $DBObject->FetchrowArray() ) {
		push @Stats2, \@Row2;
		$count2++;
    }
	
	unless ($count2) {
	my @NODATA2 = "Sorry 0 Result" ;
	push @Stats2, \@NODATA2;
	}
	
	#############################################################
		
	#DROP TEMP TABLE
	$DBObject->Do( SQL => $SQLDROP1);
	
	my @DataEmptyLine;
	push @DataEmptyLine, [ '' ];
  
	
	return ( [$Title],  [$Title], @DataEmptyLine, [@HeadData1], @Stats1, @DataEmptyLine, @DataEmptyLine, @Stats2 );
		
}

1;
