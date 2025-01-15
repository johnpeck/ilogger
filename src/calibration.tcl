# Calibration

####################### Packages and libraries #######################

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

namespace eval calibration {
    # Calibration dictionary will have slope and offset values for each gain setting (0 to 7)

    # The calibration dictionary will have the structure:
    # <serial number> slope_list <list> offset_list <list>
    variable cal_dict

    # List of connected serial numbers
    variable serial_number_list

    # The onboard calibration resistor (R7)
    variable calibration_resistor_ohms 100

    # The ADU100's AN1 input has 8 ranges: 0, 1, ... , 7
    variable current_offset_counts
    variable current_slope_counts_per_A
    foreach range [logtable::intlist -length 8] {
	array set current_offset_counts [list $range ""]
	array set current_slope_counts_per_A [list $range ""]
    }

}
