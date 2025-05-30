# Hey Emacs, use -*- Tcl -*- mode

####################### Packages and libraries #######################

# tcladu
if { [catch {package present tcladu}] } {
    try {
	set version [package require -exact tcladu 1.1.3]
	puts "Loaded tcladu version $version"
    } trap {} {message optdict} {
	puts "Error requiring tcladu"
	puts $message
	exit
    }
}

# logtable
if { [catch {package present logtable}] } {
    try {
	set version [package require logtable]
    } trap {} {message optdict} {
	puts "Failed to load logtable package:"
	puts $message
	puts ""
	puts "You can install the latest version with Tin"
	exit
    }
}

# Command-line parsing
#
# cmdline comes from tcllib
if { [catch {package present cmdline}] } {
    try {
	set version [package require cmdline]
	puts "Loaded cmdline version $version"
    } trap {} {message optdict} {
	puts "Error requiring cmdline"
	puts $message
	exit
    }
}

# Functions and variables for working with the ADU100 / Lacey (ADSM100) combination
namespace eval lacey {}

proc ::lacey::make_verbose {} {
    return "-v"
}

proc ::lacey::initialize { args } {
    # Initialize lacey-specific functions
    set usage "--> usage: initialize \[options\]"
    set myoptions {
	{adu100_index.arg "0" "ADU100 index"}
	{v "Verbose output"}
    }
    array set arg [::cmdline::getoptions args $myoptions $usage]

    # Configure digital outputs
    # CPAxxxx -- Configure data direction of PORT A ( x= 1 for input, 0 for output ) ( order is MSB-LSB )

    # PA3 -- Output initialized low for calibration relay control
    # PA2 -- Output initialized low for the LED
    # PA1 -- Input pulled up for calibration relay sensing
    # PA0 -- Output initialized low for calibration relay control

    # Make sure the status LED is off
    lacey::status_led -adu100_index $arg(adu100_index) -setting off

    # Configure direction of digital outputs
    # CPAxxxx -- Configure data direction of PORT A ( x= 1 for input, 0 for output ) ( order is MSB-LSB )
    set result [tcladu::send_command $arg(adu100_index) "CPA0010"]
    set success_code [lindex $result 0]
    if { $success_code != 0 } {
	set message "Failed to initialize ADU100 $adu100_index digital ports, "
	append message "return value was $success_code"
	error $message
    }

    # P1 -- Enables light pull-ups on I/O all lines configured as inputs.
    set result [tcladu::send_command $arg(adu100_index) "P1"]
    set success_code [lindex $result 0]
    if { $success_code != 0 } {
	set message "Failed to initialize ADU100 $adu100_index digital ports, "
	append message "return value was $success_code"
	error $message
    }
    return ok
}

proc ::lacey::open_calibration_relay { args } {
    # Open the calibration relay to disconnect the calibration resistor
    # to the output.  The output will then be high-Z.
    set usage "--> usage: open_calibration_relay \[options\]"
    set myoptions {
	{adu100_index.arg "0" "ADU100 index"}
	{v "Verbose output"}
    }
    array set arg [::cmdline::getoptions args $myoptions $usage]

    # This is a latching relay, which opens and closes with a pulse.
    # Set the width of the pulse.
    set high_time_ms 100

    # Pulse PA3 relative to PA0 to open the relay
    set result [tcladu::send_command $arg(adu100_index) "RA0"]
    set result [tcladu::send_command $arg(adu100_index) "SA3"]
    after $high_time_ms
    set result [tcladu::send_command $arg(adu100_index) "RA3"]

    # Make sure the relay opened by reading PA1
    set result [tcladu::query $arg(adu100_index) "RPA1"]
    set success_code [lindex $result 0]
    if {$success_code == 0} {
	set relay_state [lindex $result 1]
	if {$relay_state == 1} {
	    # An open relay will let PA1 be pulled up
	    if $arg(v) {
		logtable::info_message "Calibration relay is open (Rcal = Inf)"
	    }
	    return
	} else {
	    set message "Problem opening calibration relay"
	    logtable::fail_message $message
	    error $message
	}
    } else {
	set message "Problem reading PA1"
	logtable::fail_message $message
	error $message
    }
}

proc ::lacey::close_calibration_relay { args } {
    # Close the calibration relay to connect the calibration resistor
    # to the output.
    #
    # This is the relay on the Lacey board
    set usage "--> usage: close_calibration_relay \[options\]"
    set myoptions {
	{adu100_index.arg "0" "ADU100 index"}
	{v "Verbose output"}
    }
    array set arg [::cmdline::getoptions args $myoptions $usage]

    # This is a latching relay, which opens and closes with a pulse.
    # Set the width of the pulse.
    set high_time_ms 100

    # Pulse PA0 relative to PA3 to close the relay
    set result [tcladu::send_command $arg(adu100_index) "RA3"]
    set result [tcladu::send_command $arg(adu100_index) "SA0"]
    after $high_time_ms
    set result [tcladu::send_command $arg(adu100_index) "RA0"]

    # Make sure the relay closed by reading PA1
    set result [tcladu::query $arg(adu100_index) "RPA1"]
    set success_code [lindex $result 0]
    if {$success_code == 0} {
	set relay_state [lindex $result 1]
	if {$relay_state == 0} {
	    # A closed relay will pull down PA1
	    if $arg(v) {
		logtable::info_message "Calibration relay is closed (Rcal = $calibration::calibration_resistor_ohms ohms)"
	    }
	    return
	} else {
	    set message "Problem closing calibration relay"
	    logtable::fail_message $message
	    error $message
	}
    } else {
	set message "Problem reading PA1"
	logtable::fail_message $message
	error $message
    }
}

proc ::lacey::open_source_relay { args } {
    # Open the ADU100's main relay
    #
    # This is the relay inside the ADU100 (K0)
    set usage "--> usage: close_source_relay \[options\]"
    set myoptions {
	{adu100_index.arg "0" "ADU100 index"}
	{v "Verbose output"}
    }
    array set arg [::cmdline::getoptions args $myoptions $usage]

    # RK0 "resets" (opens) relay contact 0, the only relay
    set result [tcladu::send_command $arg(adu100_index) "RK0"]

    set success_code [lindex $result 0]
    set elapsed_ms [lindex $result 1]
    if { $success_code == 0 } {
	if $arg(v) {
	    logtable::info_message "Sent request to open source relay"
	}
    } else {
	set message "Failed to write 'RK0' to ADU100 $arg(adu100_index)"
	logtable::fail_message $message
	error $message
    }

    # RPK0 queries the status of relay 0
    set result [tcladu::query $arg(adu100_index) "RPK0"]
    set success_code [lindex $result 0]
    set response [lindex $result 1]
    set elapsed_ms [lindex $result 2]

    if { $success_code == 0 && $response == 0 } {
	if $arg(v) {
	    logtable::info_message "Opened source relay in $elapsed_ms ms"
	}
	return ok
    } else {
	set message "Source relay does not report being open"
	if $arg(v) {
	    logtable::fail_message $message
	}
	error $message
    }
}

proc ::lacey::close_source_relay { args } {
    # Close the ADU100's main relay
    #
    # This is the relay inside the ADU100 (K0)
    set usage "--> usage: close_source_relay \[options\]"
    set myoptions {
	{adu100_index.arg "0" "ADU100 index"}
	{v "Verbose output"}
    }
    array set arg [::cmdline::getoptions args $myoptions $usage]

    # SK0 "sets" (closes) relay contact 0, the only relay
    set result [tcladu::send_command $arg(adu100_index) "SK0"]

    set success_code [lindex $result 0]
    set elapsed_ms [lindex $result 1]
    if { $success_code == 0 } {
	if $arg(v) {
	    logtable::info_message "Sent request to close source relay"
	}
    } else {
	set message "Failed to write 'SK0' to ADU100 $arg(adu100_index)"
	logtable::fail_message $message
	error $message
    }

    # RPK0 queries the status of relay 0
    set result [tcladu::query $arg(adu100_index) "RPK0"]
    set success_code [lindex $result 0]
    set response [lindex $result 1]
    set elapsed_ms [lindex $result 2]

    if { $success_code == 0 && $response == 1 } {
	if $arg(v) {
	    logtable::info_message "Closed source relay in $elapsed_ms ms"
	}
	return ok
    } else {
	set message "Source relay does not report being closed"
	if $arg(v) {
	    logtable::fail_message $message
	}
	error $message
    }
}

proc ::lacey::calibrate_current_offset { args } {
    # Measure and write the offset value for current measurements with
    # the given range.
    #
    # Arguments:
    #   range -- 0-7 with 0 being the minimum gain (0 - 2.5V range)
    #   adu100_index -- 0, 1, ... , connected ADU100s -1
    set usage "--> usage: calibrate_current_offset \[options\]"
    set myoptions {
	{adu100_index.arg "0" "ADU100 index"}
	{range.arg "0" "0-7 with 0 being the minimum gain"}
    }
    array set arg [::cmdline::getoptions args $myoptions $usage]

    set serial_number [lindex $calibration::serial_number_list $arg(adu100_index)]
    # Close the source relay
    lacey::close_source_relay -adu100_index $arg(adu100_index)

    # Open the calibration relay (Rcal = Inf)
    lacey::open_calibration_relay -adu100_index $arg(adu100_index)
    set Rcal_ohms "Inf"

    puts ""
    puts [logtable::header_line -collist $current_offset_calibration_table::column_list]
    puts [logtable::dashline -collist $current_offset_calibration_table::column_list]

    # Readings with the calibration relay open
    set offset_sum 0
    set readings 5
    foreach reading [logtable::intlist -first 0 -length $readings] {
	# Query the signed counts from AN1
	set an1_counts [lacey::an1_counts -adu100_index $arg(adu100_index) -range $arg(range)]
	set offset_sum [expr $offset_sum + $an1_counts]
	set value_list [list $reading \
			    $Rcal_ohms \
			    $arg(range) \
			    [format %i $an1_counts]]
	puts [logtable::table_row -collist $current_offset_calibration_table::column_list -vallist $value_list]
	after 100
    }
    set offset_average [expr double($offset_sum)/$readings]

    # set calibration::current_offset_counts($arg(range)) $offset_average
    set old_offset_list [dict get $calibration::cal_dict $serial_number offset_list]
    set new_offset_list [lreplace $old_offset_list $arg(range) $arg(range) $offset_average]
    dict set calibration::cal_dict $serial_number offset_list $new_offset_list
    logtable::info_message "Range $arg(range) offset is $offset_average"
    database::write_cal_dict
    lacey::open_source_relay $arg(adu100_index)
}

proc lacey::calibrate_current_slope { args } {
    # Measure and write the slope value for current measurements with
    # the given range.
    #
    # Arguments:
    #   range -- 0-7 with 0 being the minimum gain (0 - 2.5V range)
    #   adu100_index -- 0, 1, ... , connected ADU100s -1
    set usage "--> usage: calibrate_current_slope \[options\]"
    set myoptions {
	{adu100_index.arg "0" "ADU100 index"}
	{range.arg "0" "0-7 with 0 being the minimum gain"}
	{v "Make more verbose"}
    }
    array set arg [::cmdline::getoptions args $myoptions $usage]

    set serial_number [lindex $calibration::serial_number_list $arg(adu100_index)]

    # Offset must be measured first to get an accurate slope
    set offset_counts [lindex [dict get $calibration::cal_dict $serial_number offset_list] $arg(range)]

    # Close the source relay
    lacey::close_source_relay -adu100_index $arg(adu100_index) [if $arg(v) lacey::make_verbose]

    # Close the calibration relay (Rcal = Rcal)
    close_calibration_relay -adu100_index $arg(adu100_index) [if $arg(v) lacey::make_verbose]
    set Rcal_ohms $calibration::calibration_resistor_ohms

    puts ""
    puts [logtable::header_line -collist $current_slope_calibration_table::column_list]
    puts [logtable::dashline -collist $current_slope_calibration_table::column_list]

    # Readings with the calibration relay closed
    set slope_sum_counts_per_amp 0
    set readings 5
    foreach reading [logtable::intlist -first 0 -length $readings] {
	set an1_counts [lacey::an1_counts -adu100_index $arg(adu100_index) -range $arg(range)]

	# Read Vout
	set an2_counts [lacey::an2_counts -adu100_index $arg(adu100_index)]
	# set an2_V [an2_unipolar_volts $an2_counts $config::an2_gain]
	set an2_V [lacey::an2_volts -counts $an2_counts]
	set ical_A [expr double($an2_V) / $calibration::calibration_resistor_ohms]
	set slope_counts_per_amp [expr ($an1_counts - $offset_counts) / $ical_A]
	set slope_sum_counts_per_amp [expr $slope_sum_counts_per_amp + $slope_counts_per_amp]
	set value_list [list $reading \
			    $Rcal_ohms \
			    $arg(range) \
			    "[format %0.3f $an2_V] V" \
			    "[format %0.3f [expr 1000 * $ical_A]] mA" \
			    [format %i $an1_counts] \
			    [format %0.3f $slope_counts_per_amp]]
	puts [logtable::table_row -collist $current_slope_calibration_table::column_list -vallist $value_list]
	after 100
    }
    set slope_average_counts_per_amp [expr double($slope_sum_counts_per_amp)/$readings]
    # set calibration::current_slope_counts_per_A($arg(range)) $slope_average_counts_per_amp
    set old_slope_list [dict get $calibration::cal_dict $serial_number slope_list]
    set new_slope_list [lreplace $old_slope_list $arg(range) $arg(range) $slope_average_counts_per_amp]
    dict set calibration::cal_dict $serial_number slope_list $new_slope_list
    set message "Range $arg(range) slope is [format %0.3f $slope_average_counts_per_amp] counts/Amp"
    logtable::info_message $message
    database::write_cal_dict
    open_source_relay -adu100_index $arg(adu100_index) [if $arg(v) lacey::make_verbose]
    open_calibration_relay -adu100_index $arg(adu100_index) [if $arg(v) lacey::make_verbose]
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

proc ::lacey::an1_counts {args} {
    # Return ADC counts from AN1, which is a differential input
    # between the AN1 and LCOM terminals.  The output will be signed counts:
    # -32768 --> Full-scale current flowing out of +5V terminal
    # 0      --> No current
    # +32768 --> Full-scale currrent flowing into +5V terminal
    set usage "--> usage: an1_counts \[options\]"
    set myoptions {
	{adu100_index.arg 0 "ADU100 index"}
	{range.arg "0" "0-7 with 0 being the minimum gain"}
    }
    array set arg [::cmdline::getoptions args $myoptions $usage]

    # Query the raw counts
    set result [tcladu::query $arg(adu100_index) "RBN1$arg(range)"]
    set success_code [lindex $result 0]
    if { $success_code == 0 } {
	# Query was successful
	set raw_counts [lindex $result 1]
	# These counts will be padded with leading zeros.  We need to remove them.
	set unsigned_counts [tcladu::force_integer $raw_counts]
	# 32768 is zero for signed 16-bit
	if {$unsigned_counts < 32768} {
	    set signed_counts $unsigned_counts
	} else {
	    set signed_counts [expr 32768 - $unsigned_counts]
	}
	return $signed_counts
    } else {
	return error -errorinfo "Problem querying AN1 on device $arg(adu100_index)"
    }
}

proc ::lacey::an2_counts {args} {
    # Return ADC counts from AN2, which is a single-ended input
    # looking at the +5V output.  The output will be unsigned counts.
    set usage "--> usage: an2_counts \[options\]"
    set myoptions {
	{adu100_index.arg 0 "ADU100 index"}
    }
    array set arg [::cmdline::getoptions args $myoptions $usage]

    # The voltage-measurement gain setting will likely never change,
    # so it goes in the config.
    set gain_setting $::config::an2_gain
    set result [tcladu::query $arg(adu100_index) "RUN2$gain_setting"]
    set success_code [lindex $result 0]
    if { $success_code == 0 } {
	# Query was successful
	set raw_counts [lindex $result 1]
	# These counts will be padded with leading zeros.  We need to remove them.
	set unsigned_counts [tcladu::force_integer $raw_counts]
	return $unsigned_counts
    } else {
	return error -errorinfo "Problem querying AN2 on device $arg(adu100_index)"
    }
}

proc ::lacey::an2_volts {args} {
    # Return the voltage corresponding to the ADC counts converted by
    # AN2's ADC.
    set usage "--> usage: an2_volts \[options\]"
    set myoptions {
	{counts.arg 65535 "Counts from AN2's ADC"}
    }
    array set arg [::cmdline::getoptions args $myoptions $usage]

    set gain_setting $::config::an2_gain
    if {$gain_setting == 1} {
	set voltage [expr (double($arg(counts)) / 65535) * 10.0 ]
    } else {
	set voltage [expr (double($arg(counts)) / 65535) * 5.0 ]
    }
    return $voltage
}

proc ::lacey::calibrated_current_A {args} {
    # Reads the differential voltage over the sense resistor and
    # returns an output current measurement calculated with the
    # calibration coefficients.
    set usage "--> usage: calibrated_current_A \[options\]"
    set myoptions {
	{adu100_index.arg 0 "ADU100 index"}
	{range.arg "0" "0-7 with 0 being the minimum gain"}
    }
    array set arg [::cmdline::getoptions args $myoptions $usage]

    set serial_number [lindex $calibration::serial_number_list $arg(adu100_index)]

    # Read calibration
    set slope_counts_per_amp [lindex [dict get $calibration::cal_dict $serial_number slope_list] $arg(range)]
    set offset_counts [lindex [dict get $calibration::cal_dict $serial_number offset_list] $arg(range)]

    # Read differential voltage corresponding to output current
    set an1_counts [lacey::an1_counts -adu100_index $arg(adu100_index) -range $arg(range)]

    set calibrated_measurement_A [expr (double($an1_counts) - double($offset_counts)) /\
					    double($slope_counts_per_amp)]

    return $calibrated_measurement_A

}

