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
    #
    # Slope values are in A/V
    #
    # Offset values are in A

    set default_A_per_V "11.074"
    set default_offset_A "0.01267"

    # Gain setting = 0
    dict set cal_dict 0 slope_A_per_V $default_A_per_V
    dict set cal_dict 0 offset_A $default_offset_A

    # Gain setting = 1
    dict set cal_dict 1 slope_A_per_V $default_A_per_V
    dict set cal_dict 1 offset_A $default_offset_A

    # Gain setting = 2
    dict set cal_dict 2 slope_A_per_V $default_A_per_V
    dict set cal_dict 2 offset_A $default_offset_A

    # Gain setting = 3
    dict set cal_dict 3 slope_A_per_V $default_A_per_V
    dict set cal_dict 3 offset_A $default_offset_A

    # Gain setting = 4
    dict set cal_dict 4 slope_A_per_V "11.074"
    dict set cal_dict 4 offset_A "0.01267"

    # Gain setting = 5
    dict set cal_dict 5 slope_A_per_V $default_A_per_V
    dict set cal_dict 5 offset_A $default_offset_A

    # Gain setting = 6
    dict set cal_dict 6 slope_A_per_V $default_A_per_V
    dict set cal_dict 6 offset_A $default_offset_A

    # Gain setting = 7
    dict set cal_dict 7 slope_A_per_V $default_A_per_V
    dict set cal_dict 7 offset_A $default_offset_A

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
