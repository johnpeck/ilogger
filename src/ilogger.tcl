
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
    set version [package require -exact tcladu 1.1.3.4]
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

# Calibration
source calibration.tcl

source table.tcl

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
        return -code error "not an integer: \"$x\""
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

proc initialize_adu100 { adu100_index } {
    # Claim interface 0 on the ADU100
    #
    # Arguments:
    #  adu100_index -- integer index choosing the ADU100
    set result [tcladu::initialize_device $adu100_index]
    if { $result == 0 } {
	return ok
    } else {
	colorputs -newline "Failed to initialize ADU100 $adu100_index, return value $result" red
	exit
    }
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

proc calibrate_input { adu100_index  gain_setting } {
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

proc anx_se_counts { device_index gain_setting } {
    # Return raw counts from the AN1 input
    #
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

proc A_from_V { volts gain_setting cal_dict } {
    # Return current readings in A given voltage readings
    #
    # Arguments:
    #   volts -- Voltage read from AN1
    #   gain_setting -- 0-7 with 0 being the minimum gain (0 - 2.5V range)
    #   cal_dict -- Calibration dictionary
    set slope_A_per_V [dict get $cal_dict $gain_setting slope_A_per_V]
    set offset_A [dict get $cal_dict $gain_setting offset_A]
    set amps [expr $volts * double($slope_A_per_V) + $offset_A]
    return $amps
}



namespace eval dryrun {

    # Dryrun table setup

    # Table column widths
    variable iteration_width 10
    variable counts_width 10
    variable raw_mV_width 10
    variable cal_mA_width 10
    
    
    # Alternating widths and names for the dryrun table
    set column_list [list $iteration_width "Read"]
    lappend column_list [list $counts_width "Counts"]
    lappend column_list [list $raw_mV_width "Raw (mV)"]
    lappend column_list [list $cal_mA_width "Cal (mA)"]


    
}


########################## Main entry point ##########################

# Record the invocation
set output_file_tail "cli_log.dat"
set output_file_path ${program_directory}/$output_file_tail
try {
    set fid [open $output_file_path a+]
    puts $fid $invocation
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
puts [initialize_adu100 $adu100_index]

set result [tcladu::clear_queue $adu100_index]
if { [lindex $result 0] == 0 } {
    colorputs -newline "Cleared ADU100 $adu100_index in [lindex $result 1] ms" green
} else {
    colorputs -newline "Failed to clear ADU100 $adu100_index, return value $result" red
    exit
}



# Open the datafile
set datafile "ilogger.dat"
try {
    set fid [open $datafile w+]
} trap {} {message optdict} {
    puts $message
    exit
}




close_relay $adu100_index
# Wait for reading to settle
after 1000
set raw_cal_counts [calibrate_input $adu100_index $params(g)]
set cal_counts [forceInteger $raw_cal_counts]
set cal_an1_V [anx_se_volts $cal_counts $params(g)]

puts [table::header_line $dryrun::column_list]
puts [table::dashline $dryrun::column_list]

foreach reading [iterint 0 10] {
    set raw_counts [anx_se_counts $adu100_index $params(g)]
    set an1_counts [forceInteger $raw_counts]
    set an1_V [anx_bipolar_volts $an1_counts $params(g)]
    set an1_A [A_from_V $an1_V $params(g) $cal_dict]
    set an1_mA [expr 1000 * $an1_A]
    set an1_mV [expr 1000 * $an1_V]
    set value_list [list $reading \
			[format %i $an1_counts] \
			[format %0.3f $an1_mV] \
			[format %0.3f $an1_mA]]
    puts [table::table_row $value_list $dryrun::column_list]
    # puts "AN1 counts are $an1_counts, [format %0.3f $an1_mV] mV, [format %0.3f $an1_mA] mA"
    after 1000
}



after 1000 [open_relay $adu100_index]

close $fid
exit

puts "Connected to ADU100 $adu100_index"
puts ""
puts "Logging to $datafile"
puts ""
puts "Press q<enter> to stop logging"

after 1


puts $fid "# Time (s), Current (A)"

set time_offset_s [clock seconds]

while true {
    set time_now_ms [clock milliseconds]
    set time_now_s [expr double($time_now_ms)/1000]
    # time_delta_s is a millisecond-resolution stopwatch started at
    # script execution.  The number is in floating-point seconds.
    set time_delta_s [expr $time_now_s - $time_offset_s]

    set time_stamp [format %0.3f $time_delta_s]
    send_command $vi ":measure:current:dc?"
    set result [gets $vi]
    puts "Current at $time_stamp is $result"
    puts $fid "$time_stamp, $result"
    set keypress [string trim [read stdin 1]]
    if {$keypress eq "q"} {
	break
    }
}

# close channels
close $vi
close $rm
close $fid
