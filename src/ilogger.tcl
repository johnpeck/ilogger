
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
} trap {} {message optdict} {
    puts "Error requiring logtable"
    puts $message
    exit
}

# Calibration
source calibration.tcl

source config.tcl

# Working with the Lacey board
source lacey.tcl

######################## Command-line parsing ########################

set usage "-- "
append usage "Plot sense resistor currents from ADU100"
append usage "\n\n"
append usage "usage: [file tail $thisfile] \[options\]"

lappend options [list sn.arg "" "ADU100 serial number (Empty if only one)"]
lappend options [list g.arg 0 "Analog measurement gain (0, 1, ..., 7)"]

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

proc textable_column_titles { column_list } {
    # Return a comma-separated list of column titles
    #
    # Arguments:
    #   column_list -- List of alternating column widths and titles
    foreach { width title } $column_list {
	lappend title_list $title
    }
    set csv_list [join $title_list ", "]
    return $csv_list
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

    lacey::initialize $adu100_index
    return ok
}

proc open_relay { adu100_index } {
    # Open the relay
    #
    # Arguments:
    #   adu100_index -- integer index choosing the ADU100
    set result [tcladu::send_command $adu100_index "RK0"]
    set success_code [lindex $result 0]
    if {$success_code == 0} {
	return ok
    } else {
	colorputs -newline "Problem openning the relay" red
	exit
    }
}

proc close_relay { adu100_index } {
    # Close the relay
    #
    # Arguments:
    #   adu100_index -- integer index choosing the ADU100
    set result [tcladu::send_command $adu100_index "SK0"]
    set success_code [lindex $result 0]
    if {$success_code == 0} {
	return ok
    } else {
	colorputs -newline "Problem closing the relay" red
	exit
    }
}

proc status_led {args} {
    # Turn the status LED on or off
    #
    # Arguments:
    #   adu100_index -- Which ADU100 to use
    #   setting -- on or off
    set myoptions {
	{adu100_index.arg 0 "ADU100 index"}
	{setting.arg "off" "On or off"}
    }
    array set arg [::cmdline::getoptions args $myoptions]

    if {$arg(setting) eq "on"} {
	set result [tcladu::send_command $arg(adu100_index) "SA2"]
    } else {
	set result [tcladu::send_command $arg(adu100_index) "RA2"]
    }
    set success_code [lindex $result 0]
    if {$success_code == 0} {
	return ok
    } else {
	colorputs -newline "Problem setting the status LED" red
	exit
    }

}

proc gain_from_setting { gain_setting } {
    # Return the integer gain from a gain setting value
    #
    # Arguments:
    #   gain_setting -- 0-7 with 0 being the minimum gain (0 - 2.5V range)
    set gain [expr 2**$gain_setting]
    return $gain
}

proc anx_se_volts { digitized_counts gain_setting } {
    # Convert a fixed-point single-ended AN1 or AN0 measurement to
    # floating-point volts
    #
    # Arguments:
    #   digitized_counts -- Raw output from the read/query command
    #   gain_setting -- 0-7 with 0 being the minimum gain (0 - 2.5V range)
    set gain [gain_from_setting $gain_setting]
    set voltage [expr (double($digitized_counts) / 65535) * (2.5 / $gain)]
    return $voltage
}

proc anx_bipolar_volts { digitized_counts gain_setting } {
    # Convert a fixed-point bipolar AN1 or AN0 measurement to
    # floating-point volts.
    #
    # Bipolar AN1 is just AN1 vs LCOM, which makes sense when both AN1
    # and LCOM have a positive common-mode voltage.
    #
    # Arguments:
    #   digitized_counts -- Raw output from the read/query command
    #   gain_setting -- 0-7 with 0 being the minimum gain (0 - 2.5V range)
    set gain [gain_from_setting $gain_setting]
    set voltage [expr (double($digitized_counts) / 65535 * (5.0 / $gain)) - (2.5 / $gain)]
    return $voltage
}

proc an1_bipolar_counts { device_index gain_setting } {
    # Return raw counts from the AN1 input in bipolar mode
    #
    # Bipolar AN1 is just AN1 vs LCOM, which makes sense when both AN1
    # and LCOM have a positive common-mode voltage.
    # Arguments:
    #   device_index -- 0, 1, ... , connected ADU100s -1
    #   gain_setting -- 0-7 with 0 being the minimum gain (0 - 2.5V range)
    set result [tcladu::query 0 "RBN1$gain_setting"]
    set success_code [lindex $result 0]
    if { $success_code == 0 } {
	set raw_counts [lindex $result 1]
	# These counts will be padded with leading zeros.  We need to remove them.
	set counts [forceInteger $raw_counts]
	return $counts
    } else {
	return error -errorinfo "Problem querying device $device_index"
    }
}

proc an2_unipolar_counts { device_index gain_setting } {
    # Return raw counts from the AN2 input (always unipolar)
    #
    # Arguments:
    #   device_index -- 0, 1, ... , connected ADU100s -1
    #   gain_setting -- 1 (10V max) or 2 (5V max)
    set result [tcladu::query 0 "RUN2$gain_setting"]
    set success_code [lindex $result 0]
    if { $success_code == 0 } {
	set raw_counts [lindex $result 1]
	# These counts will be padded with leading zeros.  We need to remove them.
	set counts [forceInteger $raw_counts]
	return $counts
    } else {
	return error -errorinfo "Problem querying device $device_index"
    }
}

proc an2_unipolar_volts { digitized_counts gain_setting } {
    # Convert a fixed-point bipolar AN2 measurement to floating-point
    # volts.
    #
    # Unipolar AN2 can run up to 10V with a gain setting of 1.
    #
    # Arguments:
    #   digitized_counts -- Raw output from the read/query command
    #   gain_setting -- 1 (10V max) or 2 (5V max)

    # The gain for AN2 is different than it is for other analog
    # inputs, it's just the gain setting.
    set gain $gain_setting
    set voltage [expr (double($digitized_counts) / 65535) * (10.0 / $gain)]
    return $voltage
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

namespace eval dryrun {
    # Configure the dry run table

    # Table column widths
    variable iteration_width 10
    variable counts_width 15
    variable raw_voltage_width 15
    variable cal_mA_width 15

    # Alternating widths and names for the dryrun table
    set column_list [list]
    lappend column_list [list $iteration_width "Read"]
    lappend column_list [list $counts_width "AN1 Counts"]
    lappend column_list [list $raw_voltage_width "Raw"]
    lappend column_list [list $cal_mA_width "Current"]
    lappend column_list [list $counts_width "AN2 Counts"]
    lappend column_list [list $raw_voltage_width "Voltage"]
}

namespace eval mainrun {
    # Configure the main run table

    # Table column widths
    variable time_width 10
    variable an1_counts_width 15
    variable an1_voltage_width 15
    variable cal_current_width 15
    variable an2_counts_width 15
    variable cal_voltage_width 15

    # Alternating widths and names for the mainrun table
    set column_list [list]
    lappend column_list [list $time_width "Time (s)"]
    lappend column_list [list $an1_counts_width "AN1 Counts"]
    lappend column_list [list $an1_voltage_width "Raw"]
    lappend column_list [list $cal_current_width "Current"]
    lappend column_list [list $an2_counts_width "AN2 Counts"]
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
    set serial_number_list [tcladu::serial_number_list]
    puts "Found serial numbers [join $serial_number_list]"
} trap {} {message optidict} {
    puts $message
    puts "Failed to find any ADU100s...maybe you need to plug cycle them?"
    exit
}

if {$params(sn) ne ""} {
    set adu100_index [lsearch $serial_number_list $params(sn)]
    if {$adu100_index > -1} {
	colorputs -newline "Found serial number $params(sn) at index $adu100_index" green
    }
} else {
    set adu100_index 0
}

puts -nonewline "Initializing ADU100 $adu100_index..."
puts [initialize_adu100 $adu100_index $params(g) $config::an2_gain]

lacey::calibrate_current_offset -adu100_index 0 -range $params(g)

exit

# Turn the LED on
puts [status_led -adu100_index 0 -setting "on"]
after 500
puts [status_led -adu100_index 0 -setting "off"]

# Open the datafile
# set datafile "ilogger.dat"
# try {
#     set fid [open $datafile w+]
# } trap {} {message optdict} {
#     puts $message
#     exit
# }

set fid [initialize_datafile]

close_relay $adu100_index
# Wait for reading to settle
after 1000

# Start the dry run
puts [logtable::header_line -collist $dryrun::column_list]
puts [logtable::dashline -collist $dryrun::column_list]

foreach reading [logtable::intlist -first 0 -length 10] {
    set an1_counts [an1_bipolar_counts $adu100_index $params(g)]
    set an1_V [anx_bipolar_volts $an1_counts $params(g)]
    set an1_A [A_from_V $an1_V $params(g) $calibration::cal_dict]
    set an1_mA [expr 1000 * $an1_A]
    set an1_mV [expr 1000 * $an1_V]

    set an2_counts [an2_unipolar_counts $adu100_index $config::an2_gain]
    set an2_V [an2_unipolar_volts $an2_counts $config::an2_gain]
    set value_list [list $reading \
			[format %i $an1_counts] \
			"[logtable::engineering_notation -number $an1_V -digits 3]V" \
			"[logtable::engineering_notation -number $an1_A -digits 3]A" \
			[format %i $an2_counts] \
			"[logtable::engineering_notation -number $an2_V -digits 3]V"]
    puts [logtable::table_row -collist $dryrun::column_list -vallist $value_list]
    after 1000
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
puts [logtable::header_line -collist $mainrun::column_list]
puts [logtable::dashline -collist $mainrun::column_list]

set count 0
while true {
    if { $count > 10 } {
	# Output another header line and reset the counter
	puts ""
	puts [logtable::header_line -collist $mainrun::column_list]
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
    set an1_N [an1_bipolar_counts $adu100_index $params(g)]
    set an1_V [anx_bipolar_volts $an1_N $params(g)]
    set an1_A [A_from_V $an1_V $params(g) $calibration::cal_dict]

    set an2_N [an2_unipolar_counts $adu100_index $config::an2_gain]
    set an2_V [an2_unipolar_volts $an2_N $config::an2_gain]

    # Print to real-time log
    set value_list [list $time_stamp_s \
			[format %i $an1_N] \
			"[logtable::engineering_notation -number $an1_V -digits 3]V" \
			"[logtable::engineering_notation -number $an1_A -digits 3]A" \
			[format %i $an2_N] \
			"[logtable::engineering_notation -number $an2_V -digits 3]V"]
    puts [logtable::table_row -collist $mainrun::column_list -vallist $value_list]

    puts $fid "$time_stamp_s, [format %0.3e $an2_V], [format %0.3e $an1_A]"
    set keypress [string trim [read stdin 1]]
    if {$keypress eq "q"} {
	break
    }
}

after 1000 [open_relay $adu100_index]

# close channels
close $fid
