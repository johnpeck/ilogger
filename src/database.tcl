# Database-related functions

# Use sqlitebrowser to look at database files:
# https://sqlitebrowser.org

package require sqlite3

namespace eval database {
    variable db_file "ilogger.db"

    proc create_new_db {} {

	# Open a connection to the database file
	sqlite3 db $database::db_file

	# Calibration table
	#
	# |--------+-------+--------|
	# | Serial | Slope | Offset |
	# |--------+-------+--------|
	# | BOxxxx | 23.34 | 12.34  |
	# | ...    | ...   | ...    |
	# |--------+-------+--------|
	#
	# ...where each ADU100 serial number will have a row with
	# calibration data.

	# Single quotes in SQLite are around string literals.  The name of
	# the column should be in single quotes.
	lappend column_list "'serial' TEXT"

	lappend column_list "'slope' REAL"

	lappend column_list "'offset' REAL"

	# Create the table
	db eval "CREATE TABLE 'calibration' ([join $column_list ", "])"

	db close
    }

    proc create_adu100_row {args} {
	# Create a row in the calibration table for a new ADU100
	set usage "--> usage: create_adu100_row \[options\]"
	set myoptions {
	    {serial.arg "" "Serial number"}
	    {slope.arg 0.0 "Slope"}
	    {offset.arg 0.0 "Offset"}
	}
	array set arg [::cmdline::getoptions args $myoptions $usage]

	sqlite3 db $database::db_file
	db eval "INSERT INTO 'calibration' VALUES('$arg(serial)','$arg(slope)','$arg(offset)')"

	db close

    }

    proc init_cal_dict {args} {
	# Populate the calibration dictionary from the database,
	# creating a new table for a new ADU100 if necessary.

	set usage "--> usage: init_cal_dict \[options\]"
	set myoptions {
	    {serial.arg "" "Serial number"}
	}
	array set arg [::cmdline::getoptions args $myoptions $usage]
	sqlite3 db $database::db_file

	set found_table [db eval "SELECT name FROM sqlite_master WHERE type='table' AND name='$arg(serial)'"]
	set slope_list [list]
	set offset_list [list]
	if {$found_table eq $arg(serial)} {
	    ::logtable::info_message "Reading existing $database::db_file"
	    # Read the table into a dictionary
	    foreach range [logtable::intlist -length 8] {
		db eval "SELECT * FROM $arg(serial) WHERE range = $range" values {
		    lappend offset_list $values(offset)
		    lappend slope_list $values(slope)
		}
	    }
	} else {
	    # The table for this ADU100 does not exist
	    puts "table does not exist"
	    # Create the table
	    # The table will be named with the serial number.
	    # |-------+-------+--------|
	    # | Range | Slope | Offset |
	    # |-------+-------+--------|
	    # |     0 |       |        |
	    # |     1 |       |        |
	    # |   ... |       |        |
	    # |-------+-------+--------|

	    # Single quotes in SQLite are around string literals.  The name of
	    # the column should be in single quotes.
	    lappend column_list "'range' INTEGER"

	    lappend column_list "'slope' REAL"

	    lappend column_list "'offset' REAL"
	    db eval "CREATE TABLE '$arg(serial)' ([join $column_list ", "])"
	    # Write defaults
	    set default_slope 1.0
	    set default_offset 0.0
	    foreach range [logtable::intlist -length 8] {
		db eval "INSERT INTO '$arg(serial)' VALUES('$range','$default_slope','$default_offset')"
		lappend slope_list $default_slope
		lappend offset_list $default_offset
	    }
	}
	dict set calibration::cal_dict $arg(serial) slope_list $slope_list
	dict set calibration::cal_dict $arg(serial) offset_list $offset_list

	db close
	return ok
    }

    proc write_cal_dict {args} {
	set usage "--> usage: write_cal_dict \[options\]"
	set myoptions {
	}
	array set arg [::cmdline::getoptions args $myoptions $usage]
	sqlite3 db $database::db_file
	# Delete the old tables
	foreach sn [dict keys $calibration::cal_dict] {
	    db eval "DROP TABLE $sn"
	}
	# Write new tables
	lappend column_list "'range' INTEGER"
	lappend column_list "'slope' REAL"
	lappend column_list "'offset' REAL"
	foreach sn [dict keys $calibration::cal_dict] {
	    db eval "CREATE TABLE '$sn' ([join $column_list ", "])"
	    foreach range [logtable::intlist -length 8] {
		set slope [lindex [dict get $calibration::cal_dict $sn slope_list] $range]
		set offset [lindex [dict get $calibration::cal_dict $sn offset_list] $range]
		db eval "INSERT INTO '$sn' VALUES('$range','$slope','$offset')"
	    }
	}
	db close
	return ok
    }

    proc write_adu100_calibration_row {args} {
	set usage "--> usage: write_adu100_calibration_row \[options\]"
	set myoptions {
	    {serial.arg "" "Serial number"}
	    {range.arg "" "Range"}
	}
	array set arg [::cmdline::getoptions args $myoptions $usage]
	sqlite3 db $database::db_file
	set slope $calibration::current_slope_counts_per_A($arg(range))
	set offset $calibration::current_offset_counts($arg(range))
	db eval "INSERT INTO '$arg(serial)' VALUES('$arg(range)','$slope','$offset')"
	db close
	return ok
    }
}

if {[file exists $database::db_file]} {
    # Open a connection to the database file
    sqlite3 db $database::db_file

    db close

} else {
    # Make a new database
    database::create_new_db
}
