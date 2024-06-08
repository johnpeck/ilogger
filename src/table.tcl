
namespace eval table {

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

    proc dashline { column_list } {
	# Return a string of dashes of length width
	foreach { width title } [join $column_list] {
	    incr dlength $width
	}
	
	foreach dashchar [table::iterint 0 $dlength] {
	    append dashline "-"
	}
	return $dashline
    }

    proc format_string { column_list } {
	# Return the format string for a table
	#
	# Arguments
	#   column_list -- List of alternating width and titles
	foreach {width title} [join $column_list] {
	    append fstring "%-*s "
	}
	return $fstring
    }

    proc header_line { column_list } {
	# Return the table header (formatted list of column titles)
	#
	# Arguments
	#   column_list -- List of alternating width and titles
	foreach { width title } [join $column_list] {
	    set header_bit [format "%-*s " $width $title]
	    append hline $header_bit
	}
	return $hline
    }

    proc table_row { value_list column_list } {
	# Return a table row (formatted list of column values)
	#
	# Arguments
	#   column_list -- List of alternating width and titles
	#   value_list -- List of values corresponding to the columns
	foreach {width title} [join $column_list] {
	    lappend width_list $width
	}
	foreach width $width_list value $value_list {
	    append rstring [format "%-*s " $width $value]   
	}



	return $rstring
    }

    

}
