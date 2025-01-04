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
}

if {[file exists $database::db_file]} {
    # Open a connection to the database file
    sqlite3 db $database::db_file

    db close

} else {
    # Make a new database
    database::create_new_db
}
