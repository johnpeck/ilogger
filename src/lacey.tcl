# Hey Emacs, use -*- Tcl -*- mode

####################### Packages and libraries #######################

# tcladu
try {
    set version [package require -exact tcladu 1.1.3]
    puts "Loaded tcladu version $version"
} trap {} {message optdict} {
    puts "Error requiring tcladu"
    puts $message
    exit
}

# logtable
try {
    set version [package require logtable]
} trap {} {message optdict} {
    puts "Failed to load logtable package:"
    puts $message
    puts ""
    puts "You can install the latest version with Tin"
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

# Functions and variables for working with the ADU100 / Lacey (ADSM100) combination
namespace eval lacey {

    proc initialize {adu100_index} {
	# Initialize lacey-specific functions
	#
	# Arguments:
	#  adu100_index -- integer index choosing the ADU100

	# Configure digital outputs
	# CPAxxxx -- Configure data direction of PORT A ( x= 1 for input, 0 for output ) ( order is MSB-LSB )

	# PA3 -- Output initialized low for calibration relay control
	# PA2 -- Output initialized low for the LED
	# PA1 -- Input pulled up for calibration relay sensing
	# PA0 -- Output initialized low for calibration relay control

	# Make sure the status LED is off
	lacey::status_led -adu100_index $adu100_index -setting off

	# Configure direction of digital outputs
	# CPAxxxx -- Configure data direction of PORT A ( x= 1 for input, 0 for output ) ( order is MSB-LSB )
	set result [tcladu::send_command $adu100_index "CPA0010"]
	set success_code [lindex $result 0]
	if { $success_code != 0 } {
	    set error_string "Failed to initialize ADU100 $adu100_index digital ports, "
	    append error_string "return value was $success_code"
	    logtable::colorputs -color red $error_string
	    exit
	}

	# P1      -- Enables light pull-ups on I/O all lines configured as inputs.
	set result [tcladu::send_command $adu100_index "P1"]
	set success_code [lindex $result 0]
	if { $success_code != 0 } {
	    set error_string "Failed to initialize ADU100 $adu100_index digital ports, "
	    append error_string "return value was $success_code"
	    logtable::colorputs -color $error_string
	    exit
	}
	return ok
    }

    proc open_calibration_relay {adu100_index} {
	# Open the calibration relay to disconnect the calibration resistor
	#
	# Arguments:
	#   adu100_index -- integer index choosing the ADU100
	set high_time_ms 100

	# Pulse PA3 relative to PA0 to open the relay
	set result [tcladu::send_command $adu100_index "RA0"]
	set result [tcladu::send_command $adu100_index "SA3"]
	after $high_time_ms
	set result [tcladu::send_command $adu100_index "RA3"]

	# Read PA1
	set result [tcladu::query $adu100_index "RPA1"]
	set success_code [lindex $result 0]
	if {$success_code == 0} {
	    set relay_state [lindex $result 1]
	    if {$relay_state == 1} {
		# An open relay will let PA1 be pulled up
		logtable::info_message "Calibration relay is open (Rcal = Inf)"
		return
	    } else {
		logtable::colorputs -color red "Problem opening calibration relay"
	    }
	} else {
	    logtable::colorputs -color red "Problem reading PA1"
	    exit
	}
    }

    proc close_calibration_relay {adu100_index} {
	# Close the calibration relay to connect the calibration resistor
	# to the output.
	#
	# Arguments:
	#   adu100_index -- integer index choosing the ADU100
	set high_time_ms 100

	# Pulse PA0 relative to PA3 to close the relay
	set result [tcladu::send_command $adu100_index "RA3"]
	set result [tcladu::send_command $adu100_index "SA0"]
	after $high_time_ms
	set result [tcladu::send_command $adu100_index "RA0"]

	# Read PA1
	set result [tcladu::query $adu100_index "RPA1"]
	set success_code [lindex $result 0]
	if {$success_code == 0} {
	    set relay_state [lindex $result 1]
	    if {$relay_state == 0} {
		# A closed relay will pull down PA1
		logtable::info_message "Calibration relay is closed (Rcal = $calibration::calibration_resistor_ohms ohms)"
		return
	    } else {
		logtable::colorputs -newline "Problem closing calibration relay" red
	    }
	} else {
	    logtable::colorputs -newline "Problem reading PA1" red
	    exit
	}
    }

    proc open_source_relay { adu100_index } {
	# Open the ADU100's relay
	#
	# Arguments:
	#   adu100_index -- integer index choosing the ADU100

	# RK0 "resets" (opens) relay contact 0, the only relay
	set result [tcladu::send_command 0 "RK0"]
	set success_code [lindex $result 0]
	set elapsed_ms [lindex $result 1]
	if { $success_code == 0 } {
	    # logtable::info_message "Sent request to open source relay"
	} else {
	    logtable::fail_message "Failed to write 'RK0' to ADU100 $adu100_index"
	    exit
	}

	# RPK0 queries the status of relay 0
	set result [tcladu::query 0 "RPK0"]
	set success_code [lindex $result 0]
	set response [lindex $result 1]
	set elapsed_ms [lindex $result 2]

	if { $success_code == 0 && $response == 0 } {
	    logtable::info_message "Opened source relay in $elapsed_ms ms"
	}
    }

    proc close_source_relay { adu100_index } {
	# Close the ADU100's relay
	#
	# Arguments:
	#   adu100_index -- integer index choosing the ADU100

	# SK0 "sets" (closes) relay contact 0, the only relay
	set result [tcladu::send_command 0 "SK0"]
	set success_code [lindex $result 0]
	set elapsed_ms [lindex $result 1]
	if { $success_code == 0 } {
	    # logtable::info_message "Sent request to close source relay"
	} else {
	    logtable::fail_message "Failed to write 'SK0' to ADU100 0"
	    exit
	}

	# RPK0 queries the status of relay 0
	set result [tcladu::query 0 "RPK0"]
	set success_code [lindex $result 0]
	set response [lindex $result 1]
	set elapsed_ms [lindex $result 2]

	if { $success_code == 0 && $response == 1 } {
	    logtable::info_message "Closed source relay in $elapsed_ms ms"
	}
    }

}

proc ::lacey::calibrate_current_offset { range adu100_index } {
    # Measure and write the offset value for current measurements with
    # the given range.
    #
    # Arguments:
    #   range -- 0-7 with 0 being the minimum gain (0 - 2.5V range)
    #   adu100_index -- 0, 1, ... , connected ADU100s -1

    # Close the source relay
    lacey::close_source_relay $adu100_index

    # Open the calibration relay (Rcal = Inf)
    lacey::open_calibration_relay $adu100_index
    set Rcal_ohms "Inf"

    puts ""
    puts [logtable::header_line -collist $current_offset_calibration::column_list]
    puts [logtable::dashline -collist $current_offset_calibration::column_list]

    # Readings with the calibration relay open
    set offset_sum 0
    set readings 5
    foreach reading [logtable::intlist -first 0 -length $readings] {
	set an1_raw_counts [an1_bipolar_counts $adu100_index $range]
	# 32768 is zero for signed 16-bit
	if {$an1_raw_counts < 32768} {
	    set an1_signed_counts $an1_raw_counts
	} else {
	    set an1_signed_counts [expr 32768 - $an1_raw_counts]
	}
	set offset_sum [expr $offset_sum + $an1_signed_counts]
	set value_list [list $reading \
			    $Rcal_ohms \
			    $range \
			    [format %i $an1_raw_counts] \
			    [format %i $an1_signed_counts]]
	puts [logtable::table_row -collist $current_offset_calibration::column_list -vallist $value_list]
	after 100
    }
    set offset_average [expr double($offset_sum)/$readings]

    set calibration::current_offset_counts($range) $offset_average
    logtable::info_message "Range $range offset is $calibration::current_offset_counts($range)"
    lacey::open_source_relay $adu100_index
}

proc ::lacey::status_led {args} {
    # Turn the status LED on or off
    #
    # Arguments:
    #   adu100_index -- Which ADU100 to use
    #   setting -- on or off
    set usage "--> usage: status_led \[options\]"
    set myoptions {
	{adu100_index.arg 0 "ADU100 index"}
	{setting.arg "off" "On or off"}
    }
    array set arg [::cmdline::getoptions args $myoptions $usage]

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

########################### Define tables ############################

namespace eval current_offset_calibration {
    # Configure the current offset calibration table

    # Table column widths
    variable iteration_width 10
    variable counts_width 12

    # Alternating widths and names for the table
    lappend column_list [list $iteration_width "Read"]
    lappend column_list [list $iteration_width "Rcal"]
    lappend column_list [list $iteration_width "Range"]
    lappend column_list [list $counts_width "Raw N"]
    lappend column_list [list $counts_width "Signed N"]
}
