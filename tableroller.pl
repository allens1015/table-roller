#!/usr/bin/perl

# next: make the table use sets- 
# [
#   3d6g
#   2d8sp
#   1scroll
# ]
# as one hit from origin
use JSON;
use Data::Dumper;

# condense
my ($origin_path,$origin,$initial_count,$value_limit);
my $data_path = "data/";

foreach my $arg (@ARGV) {
	if($arg =~ /--o=(.*)/) { $origin = $1; }
  if($arg =~ /--ic=(\d+)/) { $initial_count = $1; }
  if($arg =~ /--v=(\d+)/) { $value_limit = $1; }
}

unless($origin) {
  $origin = "origin";
}
$origin_path = $data_path.$origin.".json";
unless($initial_count) {
  $initial_count = 1;
}

# get origin data in
my $origin_json = decode_json &get_json($origin_path);

# start rolling
my ($done,$loot);
while(!$done) {
  # print "start: $origin_path\n";
  ($done,$loot) = &roll_table($origin_json,$origin_path,$value_limit,$loot);
  $initial_count--;
  if($done and $initial_count) {
    undef $done;
  }
}
print Dumper $loot;

# ------------------------------
sub get_json {
  my ($path) = @_;
  my $data;

  open my $fh, "<", $path;
    while(my $row = <$fh>) {
      $data .= $row;
    }
  close $fh;

  return $data;
}

# ------------------------------
sub roll_table {
  my ($json_in,$json_path,$value_limit,$loot) = @_;
  my @data = @$json_in;
  # print "starting &roll_table()\n";

  my @loot_items;
  my $within_value_bounds;

  # determine breakpoints for rolling
  my $total_weight = 0;
  my @breakpoints;
  my $valid_table = 1;
  foreach my $row (@data) {
    if($row->{min_value} and $value_limit) {
      if($row->{min_value} > $value_limit) {
        undef $valid_table;
      }
    }
    if($valid_table) {
      my $breakpoint = $row->{weight} + $total_weight;
      push(@breakpoints,$breakpoint);
      $total_weight += $row->{weight};
    }
  }

  # get a roll
  my $roll = &rng($total_weight);

  # get the correct table index
  my $i = 0;
  foreach my $breakpoint (@breakpoints) {
    if($roll <= $breakpoint) {
      last;
    }
    $i++;
  }

  # process row winner
  my $selected_row = $data[$i];
  # print Dumper $selected_row;
  # if the winner is a table...
  if($selected_row->{type} eq "table") {
    # source the data for that table
    my $next_table_path = $data_path.$selected_row->{name}.".json";
    my $next_table = decode_json &get_json($next_table_path);
    # print Dumper $next_table;
    
    # find out how many times you gotta roll on that table
    my $count_info = &get_count_info($selected_row->{count});
    
    while($count_info->{die_count}) {
      my $roll = &rng($count_info->{die_step});
      $count_info->{times_to_roll} += $roll;
      $count_info->{die_count}--;
    }

    # roll that table that many times
    while($count_info->{times_to_roll}) {
      # recursion
      ($done,$loot) = &roll_table($next_table,$next_table_path,$value_limit,$loot);
      $count_info->{times_to_roll}--;
    }  
  }
  # if you need to add to the loot "table" and continue rolling eg +1 flaming longsword
  elsif($selected_row->{type} eq "add") {
    my $next_table_path = $data_path.$selected_row->{continue_name}.".json";
    my $next_table = decode_json &get_json($next_table_path);

    my $count_info = &get_count_info($selected_row->{count});
    
    while($count_info->{die_count}) {
      my $roll = &rng($count_info->{die_step});
      $count_info->{times_to_roll} += $roll;
      $count_info->{die_count}--;
    }

    # roll that table that many times
    while($count_info->{times_to_roll}) {
      # recursion
      my $loot_name = $selected_row->{name};
      push(@loot_items,$loot_name);
      if($loot->{items}) {
        push(@loot_items,@{$loot->{items}});
      }
      $loot->{items} = \@loot_items;
      ($done,$loot) = &roll_table($next_table,$next_table_path,$value_limit,$loot);
      $count_info->{times_to_roll}--;
    }
  }
  # if its not a table
  else {
    # get the items, then push to an array, then concat with existing items
    my $loot_name = $selected_row->{name};
    my $loot_name_modifier = &generate_name_modifier($json_path);
    my $value = $selected_row->{value};
    if($loot_name_modifier) {
      $loot_name .= $loot_name_modifier;
    }
    if($value) {
      $loot_name .= " ($value)";
    }
    $json_path =~ s/data\/(.*)\.json$/$1/;
    $loot_name .= " // $json_path";
    push(@loot_items,$loot_name);
    if($loot->{items}) {
      push(@loot_items,@{$loot->{items}});
    }
    $loot->{items} = \@loot_items;
    # return done for non-recursive table
    return (1,$loot);
  }

  # return totality
  return ($done,$loot);
}

# ------------------------------
sub generate_name_modifier {
  my ($json_path) = @_;
  my ($level,$school,$name_modifier);
  if($json_path =~ /\/(\d)_/) {
    $level = "$1";
  }
  if($json_path =~ /(arcane|divine)/) {
    $school = $1;
  }
  if(($level or $level eq 0) and !$school) {
    $name_modifier = " ($level)";
  }
  elsif($school and (!$level and $level ne 0)) {
    $name_modifier = " ($school)";
  }
  elsif($school and ($level or $level eq 0)) {
    $name_modifier = " ($school $level)";
  }

  return $name_modifier;
}

# ------------------------------
sub rng {
  my ($max) = @_;
  return int(rand($max))+1;
}

# ------------------------------
sub get_count_info {
  my ($count_str) = @_;
  
  my $count_info;

  if($count_str) {
    my @count_data = split(/\+/,$count_str);
    $count_data[0] =~ /(\d+)d(\d+)/;
    ($count_info->{die_count},$count_info->{die_step}) = (int($1),int($2));
    $count_info->{mod} = $count_data[1];
    $count_info->{mod} =~ s/\+//;
    $count_info->{mod} = int($count_info->{mod});
    $count_info->{times_to_roll} = $count_info->{mod};
  }
  else {
    $count_info->{times_to_roll} = 1;
  }

  return $count_info;
}