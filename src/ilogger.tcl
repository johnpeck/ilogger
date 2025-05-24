
# Hey Emacs, use -*- Tcl -*- mode

########################## Program details ###########################

set thisfile [file normalize [info script]]

# The name of this program.  This will get used to identify logfiles,
# configuration files and other file outputs.
set program_name [file rootname [file tail $thisfile]]

# Directory where this script lives
set program_directory [file dirname $thisfile]

# Directory from which the script was invoked
set invoked_directory [pwd]

####################### Packages and libraries #######################

# Tin installs user packages in ~/.local/share/tcltk.  We need to add
# that to the package search list.
lappend auto_path "~/.local/share/tcltk"

# Load tcladu
try {
    set version [package require -exact tcladu 1.1.3]
    puts "Loaded tcladu version $version"
} trap {} {message optdict} {
    puts "Error requiring tcladu"
    puts $message
    exit
}

# Command-line parsing
#
# cmdline comes from tcllib
try {
    set version [package require cmdline]
    puts "Loaded cmdline version $version"
} trap {} {message optdict} {
    puts "Error requiring cmdline"
    puts $message
    exit
}

# Datafile metadata from inifile
#
# inifile comes from tcllib
try {
    set version [package require inifile]
    puts "Loaded inifile version $version"
    ini::commentchar "#"
} trap {} {message optdict} {
    puts "Error requiring inifile"
    puts $message
    exit
}

# Logtable for tabular console logging
try {
    set version [package require logtable]
    puts "Loaded logtable version $version"
    set action_script [package ifneeded logtable $version]
    puts "  Action script is:"
    foreach line [split $action_script "\n"] {
	puts "  $line"
    }
} trap {} {message optdict} {
    puts "Error requiring logtable"
    puts $message
    exit
}

# Calibration
source calibration.tcl

source config.tcl

# Database
source database.tcl

# Working with the Lacey board
source lacey.tcl

# Text table definitions
source tables.tcl

######################## Command-line parsing ########################

set usage "-- "
append usage "Plot sense resistor currents from ADU100"
append usage "\n\n"
append usage "usage: [file tail $thisfile] \[options\]"

lappend options [list sn.arg "" "ADU100 serial number (Empty if only one)"]
lappend options [list g.arg 0 "Analog measurement gain (0, 1, ..., 7)"]
lappend options [list c "Calibrate single range (specified by -g) and exit"]
lappend options [list ca "Calibrate all ranges and exit"]
lappend options [list d "Dry run and exit"]
lappend options [list v "Make more verbose"]

set invocation "tclsh ilogger.tcl $argv"
try {
    array set params [::cmdline::getoptions argv $options $usage]
} trap {CMDLINE USAGE} {msg o} {
    # Trap the usage signal, print the message, and exit the application.
    # Note: Other errors are not caught and passed through to higher levels!
    puts $msg
    exit 1
}

proc iterint {start points} {
    # Return a list of increasing integers starting with start with
    # length points
    set count 0
    set intlist [list]
    while {$count < $points} {
	lappend intlist [expr $start + $count]
	incr count
    }
    return $intlist
}

proc forceInteger { x } {
    # https://stackoverflow.com/questions/2110864/handling-numbers-with-leading-zeros-in-tcl
    set count [scan $x %d%s n rest]
    if { $count <= 0 || ( $count == 2 && ![string is space $rest] ) } {
        return -code error "Not an integer: \"$x\""
    }
    return $n
}

proc colorputs {newline text color} {

    set colorlist [list black red green yellow blue magenta cyan white]
    set index 30
    foreach fgcolor $colorlist {
	set ansi(fg,$fgcolor) "\033\[1;${index}m"
	incr index
    }
    set ansi(reset) "\033\[0m"
    switch -nocase $color {
	"red" {
	    puts -nonewline "$ansi(fg,red)"
	}
	"green" {
	    puts -nonewline "$ansi(fg,green)"
	}
	"yellow" {
	    puts -nonewline "$ansi(fg,yellow)"
	}
	"blue" {
	    puts -nonewline "$ansi(fg,blue)"
	}
	"magenta" {
	    puts -nonewline "$ansi(fg,magenta)"
	}
	"cyan" {
	    puts -nonewline "$ansi(fg,cyan)"
	}
	"white" {
	    puts -nonewline "$ansi(fg,white)"
	}
	default {
	    puts "No matching color"
	}
    }
    switch -exact $newline {
	"-nonewline" {
	    puts -nonewline "$text$ansi(reset)"
	}
	"-newline" {
	    puts "$text$ansi(reset)"
	}
    }

}

proc calibrate_an1 { adu100_index  gain_setting } {
    # Have the ADU100 perform an auto-calibration on the AN1 analog
    # input in bipolar mode.
    #
    # Arguments:
    #   adu100_index -- integer index choosing the ADU100
    #   gain_setting -- 0-7 with 0 being the minimum gain (0 - 2.5V range)

    if { $gain_setting <= 7 && $gain_setting >= 0 } {
	# This is fine
    } else {
	set gain_setting 0
    }
    # Calibrate input 1 with a gain of gain_setting
    set result [tcladu::query $adu100_index "RBC1$gain_setting"]
    set success_code [lindex $result 0]
    if {$success_code == 0} {
	set value [lindex $result 1]
	# puts "Returned value was $value"
	return $value
    } else {
	colorputs -newline "Problem calibrating AN1" red
	exit
    }
}

proc calibrate_an2 { adu100_index  gain_setting } {
    # Have the ADU100 perform an auto-calibration on the AN2 analog
    # input in unipolar mode.
    #
    # Arguments:
    #   adu100_index -- integer index choosing the ADU100
    #   gain_setting -- 1 (10V max) or 2 (5V max)

    if { $gain_setting <= 2 && $gain_setting >= 1 } {
	# This is fine
    } else {
	set gain_setting 1
    }
    # Calibrate AN2 with a gain of gain_setting
    set result [tcladu::query $adu100_index "RUC2$gain_setting"]
    set success_code [lindex $result 0]
    if {$success_code == 0} {
	set value [lindex $result 1]
	# puts "Returned value was $value"
	return $value
    } else {
	colorputs -newline "Problem calibrating AN2" red
	exit
    }
}

proc initialize_adu100 { adu100_index an1_gain an2_gain } {
    # Claim interface 0 on the ADU100
    #
    # Arguments:
    #  adu100_index -- integer index choosing the ADU100
    set result [tcladu::initialize_device $adu100_index]
    if { $result != 0 } {
	logtable::colorputs -color red "Failed to initialize ADU100 $adu100_index, return value $result"
	exit
    }
    set result [tcladu::clear_queue $adu100_index]
    if { [lindex $result 0] == 0 } {
	logtable::colorputs -color green "Cleared ADU100 $adu100_index in [lindex $result 1] ms"
    } else {
	logtable::colorputs -color red "Failed to clear ADU100 $adu100_index, return value $result"
	exit
    }

    # The analog inputs need to be calibrated in case the gain setting has changed.
    calibrate_an1 $adu100_index $an1_gain
    calibrate_an2 $adu100_index $an2_gain

    lacey::initialize -adu100_index $adu100_index
    return ok
}

proc gain_from_setting { gain_setting } {
    # Return the integer gain from a gain setting value
    #
    # Arguments:
    #   gain_setting -- 0-7 with 0 being the minimum gain (0 - 2.5V range)
    set gain [expr 2**$gain_setting]
    return $gain
}

proc A_from_V { volts gain_setting cal_dict } {
    # Return current readings in A given voltage readings
    #
    # Arguments:
    #   volts -- Voltage read from AN1
    #   gain_setting -- 0-7 with 0 being the minimum gain (0 - 2.5V range)
    #   cal_dict -- Calibration dictionary
    set slope_A_per_V [dict get $calibration::cal_dict $gain_setting slope_A_per_V]
    set offset_A [dict get $calibration::cal_dict $gain_setting offset_A]
    set amps [expr $volts * double($slope_A_per_V) + $offset_A]
    return $amps
}

proc current_A { adu100_index gain_setting } {
    # Return the current measurement in Amps
    #
    # Arguments:
    #   adu100_index -- integer index choosing the ADU100
    #   gain_setting -- Gain setting 0-7 with 0 being the minimum gain (0 - 2.5V range)

    # Make the AN1 reading
    set an1_counts [an1_bipolar_counts $adu100_index $gain_setting]

    # Convert AN1 counts to volts
    set an1_V [anx_bipolar_volts $an1_counts $gain_setting]

    # Convert voltage to current using the calibration dictionary
    set an1_A [A_from_V $an1_V $gain_setting $calibration::cal_dict]
    return $an1_A
}

proc pdict {dict {pattern *}} {
   set longest 0
   dict for {key -} $dict {
      if {[string match $pattern $key]} {
         set longest [expr {max($longest, [string length $key])}]
      }
   }
   dict for {key value} [dict filter $dict key $pattern] {
      puts [format "%-${longest}s = %s" $key $value]
   }
}

proc initialize_datafile {} {
    # Initialize the datafile and return a file pointer
    set datafile "ilogger.dat"
    try {
	set fid [open $datafile w+]
    } trap {} {message optdict} {
	puts $message
	exit
    }
    puts $fid "\[about\]"
    puts $fid ""
    puts $fid "# The title for the data to appear in the plot key"
    puts $fid "title=some crap"
    puts $fid ""
    puts $fid "# No more keys below the data section"
    puts $fid "\[data\]"
    puts $fid ""
    return $fid
}

proc make_verbose {} {
    return "-v"
}

proc test_calibration { args } {
    # Test the current measurement in one range
    set usage "--> usage: test_calibration \[options\]"
    set myoptions {
	{adu100_index.arg 0 "ADU100 index"}
	{range.arg "0" "0-7 with 0 being the minimum gain"}
	{v "Make more verbose"}
    }
    array set arg [::cmdline::getoptions args $myoptions $usage]
    set serial_number [lindex $calibration::serial_number_list $arg(adu100_index)]

    # Close the source relay
    lacey::close_source_relay -adu100_index $arg(adu100_index) [if $arg(v) make_verbose]

    # Close the calibration relay (Rcal = Rcal)
    lacey::close_calibration_relay -adu100_index $arg(adu100_index) [if $arg(v) make_verbose]
    set Rcal_ohms $calibration::calibration_resistor_ohms

    puts ""
    puts [logtable::header_line -collist $calibration_check_table::column_list]
    puts [logtable::dashline -collist $calibration_check_table::column_list]

    # Readings with the calibration relay closed
    set measured_current_sum_amps 0
    set readings 5
    foreach reading [logtable::intlist -first 0 -length $readings] {

	# Read differential voltage corresponding to output current
	set an1_counts [lacey::an1_counts -adu100_index $arg(adu100_index) -range $arg(range)]

	# Read Vout
	set an2_counts [lacey::an2_counts -adu100_index $arg(adu100_index)]
	set an2_V [lacey::an2_volts -counts $an2_counts]

	# Calculated calibration current based on calibration resistor
	set ical_A [expr double($an2_V) / $calibration::calibration_resistor_ohms]
	set slope_counts_per_amp [lindex [dict get $calibration::cal_dict $serial_number slope_list] $arg(range)]
	set offset_counts [lindex [dict get $calibration::cal_dict $serial_number offset_list] $arg(range)]
	set calibrated_measurement_amps [expr (double($an1_counts) - double($offset_counts)) /\
					    double($slope_counts_per_amp)]

	set measured_current_sum_amps [expr $measured_current_sum_amps + $calibrated_measurement_amps]
	set value_list [list $reading \
			    $Rcal_ohms \
			    $arg(range) \
			    "[format %0.3f $an2_V] V" \
			    "[format %0.3f [expr 1000 * $ical_A]] mA" \
			    [format %i $an1_counts] \
			    [format %0.3f $slope_counts_per_amp] \
			    [format %0.3f $offset_counts] \
			    "[format %0.3f [expr 1000 * $calibrated_measurement_amps]] mA"]
	puts [logtable::table_row -collist $calibration_check_table::column_list -vallist $value_list]
	after 100
    }
    set current_average_milliamps [expr double($measured_current_sum_amps)/$readings * 1000]

    # Report calibrated measurement
    set message "Measurement in range $arg(range) slope is [format %0.3f $current_average_milliamps] mA"
    logtable::info_message $message

    # Report range full scale
    #
    # Full scale in Amps is (32767 - offset)/slope
    set full_scale_A [expr -(32767 - $offset_counts)/double($slope_counts_per_amp)]
    set message "Range $arg(range) full scale is [logtable::engineering_notation -number $full_scale_A -digits 3]A"
    logtable::info_message $message

    lacey::open_source_relay -adu100_index $arg(adu100_index)
    lacey::open_calibration_relay $arg(adu100_index)

    # Measurement should be within 1mA of 50mA
    set correct [expr ($current_average_milliamps >= 49) && ($current_average_milliamps <= 51)]
    if $correct {
	logtable::pass_message "Calibration test passes"
	return
    } else {
	logtable::fail_message "Failed to calibrate current measurement"
	exit
    }
}

namespace eval dryrun {
    # Configure the dry run table

    # Table column widths
    variable iteration_width 10
    variable counts_width 15
    variable voltage_width 15
    variable current_width 15

    # Alternating widths and names for the dryrun table
    set column_list [list]
    lappend column_list [list $iteration_width "Read"]
    lappend column_list [list $iteration_width "Range"]
    lappend column_list [list $voltage_width "Voltage"]
    lappend column_list [list $counts_width "AN1 (N)"]
    lappend column_list [list $counts_width "Slope (N/A)"]
    lappend column_list [list $counts_width "Offset (N)"]
    lappend column_list [list $current_width "Current"]

}

namespace eval mainrun {
    # Configure the main run table

    # Table column widths
    variable time_width 10
    variable cal_current_width 15
    variable cal_voltage_width 15

    # Alternating widths and names for the mainrun table
    set column_list [list]
    lappend column_list [list $time_width "Time (s)"]
    lappend column_list [list $cal_current_width "Current"]
    lappend column_list [list $cal_voltage_width "Voltage"]
}

########################## Main entry point ##########################

# Record the invocation
set output_file_tail "cli_log.dat"
set output_file_path ${program_directory}/$output_file_tail
try {
    set fid [open $output_file_path a+]
    set timestamp [clock format [clock seconds] -format {<%d-%b-%Y %H:%M>}]
    puts $fid "$timestamp $invocation"
    close $fid
} trap {} {message optdict} {
    puts $message
    exit
}

try {
    set calibration::serial_number_list [tcladu::serial_number_list]
    puts "Found serial numbers [join $calibration::serial_number_list]"
} trap {} {message optidict} {
    puts $message
    puts "Failed to find any ADU100s...maybe you need to plug cycle them?"
    exit
}

if {$params(sn) ne ""} {
    set adu100_index [lsearch $calibration::serial_number_list $params(sn)]
    if {$adu100_index > -1} {
	colorputs -newline "Found serial number $params(sn) at index $adu100_index" green
    }
} else {
    set adu100_index 0
}
set serial_number [lindex $calibration::serial_number_list $adu100_index]

puts -nonewline "Initializing ADU100 $adu100_index..."
puts [initialize_adu100 $adu100_index $params(g) $config::an2_gain]

database::init_cal_dict -serial [lindex $calibration::serial_number_list $adu100_index]

logtable::info_message "Read in calibration data:"
# pdict $calibration::cal_dict

if $params(c) {
    # Calibrate in the chosen current range and exit
    lacey::calibrate_current_offset -adu100_index 0 -range $params(g)

    # pdict $calibration::cal_dict
    lacey::calibrate_current_slope -adu100_index 0 -range $params(g)
    # pdict $calibration::cal_dict
    test_calibration -adu100_index 0 -range $params(g) [if $params(v) make_verbose]
    exit
}

if $params(ca) {
    # Calibrate all ranges and exit
    #
    # We can only directly calibrate ranges 0 --> 5 with a 50mA
    # calibration current and a 1-ohm sense resistor.
    foreach range [logtable::intlist -first 0 -length 6] {
	# Calibrate in the chosen current range and exit
	lacey::calibrate_current_offset -adu100_index 0 -range $range

	lacey::calibrate_current_slope -adu100_index 0 -range $range

	test_calibration -adu100_index 0 -range $range [if $params(v) make_verbose]
    }
    exit
}

# Turn the LED on
puts [lacey::status_led -adu100_index 0 -setting "on"]
after 500
puts [lacey::status_led -adu100_index 0 -setting "off"]

set fid [initialize_datafile]

if $params(d) {
    # Start the dry run
    lacey::close_source_relay -adu100_index $adu100_index -v

    # Wait for reading to settle
    after 1000

    puts [logtable::header_line -collist $dryrun::column_list]
    puts [logtable::dashline -collist $dryrun::column_list]
    foreach reading [logtable::intlist -first 0 -length 10] {

	# Read differential voltage corresponding to output current
	set an1_counts [lacey::an1_counts -adu100_index $adu100_index -range $params(g)]

	# Read Vout
	set an2_counts [lacey::an2_counts -adu100_index $adu100_index]
	set an2_V [lacey::an2_volts -counts $an2_counts]

	set slope_counts_per_amp [lindex [dict get $calibration::cal_dict $serial_number slope_list] $params(g)]
	set offset_counts [lindex [dict get $calibration::cal_dict $serial_number offset_list] $params(g)]
	set calibrated_measurement_A [lacey::calibrated_current_A -adu100_index $adu100_index -range $params(g)]

	set value_list [list $reading \
			    $params(g) \
			    "[logtable::engineering_notation -number $an2_V -digits 4]V" \
			    $an1_counts \
			    "[logtable::engineering_notation -number $slope_counts_per_amp -digits 5]" \
			    $offset_counts \
			    "[logtable::engineering_notation -number $calibrated_measurement_A -digits 6]A"]

	puts [logtable::table_row -collist $dryrun::column_list -vallist $value_list]

	# Time between samples
	after 100

    }
    lacey::open_source_relay -adu100_index $adu100_index
    exit
}

puts ""
puts "Press q<enter> to stop logging"

# Allow keyboard input during data collection.  We need to use the
# keyboard to stop collection.
chan configure stdin -blocking 0 -buffering none

after 1

puts $fid "# Time (s), Voltage (V), Current (A)"

set time_offset_s [clock seconds]

# Start the main run
lacey::close_source_relay -adu100_index $adu100_index

puts [logtable::header_line -collist $mainrun::column_list]
puts [logtable::dashline -collist $mainrun::column_list]

set count 0
while true {
    if { $count > 10 } {
	# Output another header line and reset the counter
	puts ""
	puts -nonewline [logtable::header_line -collist $mainrun::column_list]
	puts "Press q<enter> to quit"
	puts [logtable::dashline -collist $mainrun::column_list]
	set count 0
    } else {
	incr count
    }
    set time_now_ms [clock milliseconds]
    set time_now_s [expr double($time_now_ms)/1000]
    # time_delta_s is a millisecond-resolution stopwatch started at
    # script execution.  The number is in floating-point seconds.
    set time_delta_s [expr $time_now_s - $time_offset_s]

    set time_stamp_s [format %0.3f $time_delta_s]

    # Collect data
    set calibrated_measurement_A [lacey::calibrated_current_A -adu100_index $adu100_index -range $params(g)]

    set an2_counts [lacey::an2_counts -adu100_index $adu100_index]
    set an2_V [lacey::an2_volts -counts $an2_counts]

    # Print to real-time log
    set value_list [list $time_stamp_s \
			"[logtable::engineering_notation -number $calibrated_measurement_A -digits 3]A" \
			"[logtable::engineering_notation -number $an2_V -digits 3]V"]
    puts [logtable::table_row -collist $mainrun::column_list -vallist $value_list]

    puts $fid "$time_stamp_s, [format %0.3e $an2_V], [format %0.3e $calibrated_measurement_A]"
    set keypress [string trim [read stdin 1]]
    if {$keypress eq "q"} {
	lacey::open_source_relay -adu100_index $adu100_index
	break
    }
}

# close channels
close $fid
