# Hey Emacs, use -*- Tcl -*- mode

# Table definitions

namespace eval current_offset_calibration {
    # Configure the current offset calibration table

    # Table column widths
    variable iteration_width 10
    variable counts_width 12

    # Alternating widths and names for the table
    lappend column_list [list $iteration_width "Read"]
    lappend column_list [list $iteration_width "Rcal"]
    lappend column_list [list $iteration_width "Range"]
    lappend column_list [list $counts_width "Offset"]
}

namespace eval current_slope_calibration {
    # Configure the current slope calibration table

    # Table column widths
    variable iteration_width 10
    variable counts_width 12
    variable current_width 12

    # Alternating widths and names for the table
    lappend column_list [list $iteration_width "Read"]
    lappend column_list [list $iteration_width "Rcal"]
    lappend column_list [list $iteration_width "Range"]
    lappend column_list [list $current_width "Vout"]
    lappend column_list [list $current_width "Cal I"]
    lappend column_list [list $counts_width "Signed N"]
    lappend column_list [list $current_width "Slope"]
}

namespace eval calibration_check_table {
    # Configure the calibration check table

    # Table column widths
    variable iteration_width 10
    variable counts_width 12
    variable measurement_width 12

    # Alternating widths and names for the table
    lappend column_list [list $iteration_width "Read"]
    lappend column_list [list $iteration_width "Rcal"]
    lappend column_list [list $iteration_width "Range"]
    lappend column_list [list $measurement_width "Vout"]
    lappend column_list [list $measurement_width "Cal I"]
    lappend column_list [list $counts_width "Signed N"]
    lappend column_list [list $measurement_width "Slope"]
    lappend column_list [list $measurement_width "Offset"]
    lappend column_list [list $measurement_width "Calibrated"]
}
