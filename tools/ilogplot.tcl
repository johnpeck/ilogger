# Hey Emacs, use -*- Tcl -*- mode

########################## Program details ###########################

# The name of this program.  This will get used to identify logfiles,
# configuration files and other file outputs.
set program_name ilogplot

set thisfile [file normalize [info script]]

# Directory where this script lives
set program_directory [file dirname $thisfile]

# Directory from which the script was invoked
set invoked_directory [pwd]

# Does this need input data files?
set takes_input_files true

####################### Packages and libraries #######################

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

# General helper functions
try {
    set version [package require logtable]
    puts "Loaded logtable version $version"
} trap {} {message optdict} {
    puts "Error requiring logtable"
    puts $message
    exit
}

############################# Constants ##############################

namespace eval constants {
    # Put constants here
    set r15_ohms 56
}

####################### Command-line Arguments #######################

set usage "usage: [file tail $thisfile] \[options] datafiles"

# Plot title
lappend options {t.arg "Current draw" "Overall plot title"}

# Padding -- makes room for current labels at the beginning of the plot
lappend options {p.arg "0" "Padding at beginning of plot (s)"}

# Current reference lines
lappend options {cr1.arg "" "Current reference line 1"}
lappend options {cr2.arg "" "Current reference line 2"}

# Voltage references
foreach reference [logtable::intlist -first 1  -length 5] {
    lappend options [list vr${reference}.arg "" "Voltage reference $reference"]
}

# Current references
foreach reference [logtable::intlist -first 1 -length 5] {
    lappend options [list ir${reference}.arg "" "Current reference $reference"]
}

try {
    array set params [::cmdline::getoptions argv $options $usage]
} trap {CMDLINE USAGE} {msg o} {
    # Trap the usage signal, print the message, and exit the application.
    # Note: Other errors are not caught and passed through to higher levels!
    puts $msg
    exit 1
}

# After cmdline is done, argv will point to the last argument
set input_file_name_list [list]
foreach filename $argv {
    lappend input_file_name_list $filename
}

if {[llength $input_file_name_list] == 0} {
    # There were no input files
    if $takes_input_files {
	puts $usage
	exit
    }
}

####################### Gnuplot configuration ########################

switch -exact $tcl_platform(os) {
    "Windows NT" {
	# Path to gnuplot executable
	set gnuplot "c:/Users/jopeck/AppData/Local/Programs/gnuplot/bin/wgnuplot.exe"

	# The wxt terminal can keep windows alive after the gnuplot process
	# exits.  This allows calling multiple persistent windows which allow
	# zooming and annotation.
	set gnuplot_terminal "wxt font 'Arial,12'"
    }
    "Linux" {
	# Path to gnuplot executable
	set gnuplot gnuplot

	# The wxt terminal can keep windows alive after the gnuplot process
	# exits.  This allows calling multiple persistent windows which allow
	# zooming and annotation.
	set gnuplot_terminal "wxt font 'Arial,12'"
    }

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

proc file_name_with_context {full_file_path} {
    set file_parts_list [file split $full_file_path]
    set found_projects false
    foreach part $file_parts_list {
	if {$part eq "projects"} {
	    set found_projects true
	}
	if { ! $found_projects } {
	    continue
	}
	append name_with_context "${part} / "
    }
    return [string trim $name_with_context "/ "]
}

proc read_file {filename datafile_dict_list} {
    # Return a dictionary of data from the input filename
    #
    # Arguments:
    #   filename -- relative or full path to file
    #   datafile_dict_list -- List of dictionaries to be appended

    # Read the metadata
    set fp [ini::open $filename]

    puts "Opened [ini::filename $fp]"

    puts "Found sections: [ini::sections $fp]"

    puts "Comment character is [ini::commentchar]"

    puts "Found keys: [ini::keys $fp about] in the about section"

    foreach key [ini::keys $fp about] {
	dict set datafile_dict $key [ini::value $fp about $key]
    }

    ini::close $fp

    try {
	set fid [open $filename r]
	puts "* Reading from $filename"
    } trap {} {message optdict} {
	puts $message
	exit
    }
    set delimiter ","
    set raw_datafile_list [split [read $fid] "\n"]

    foreach line $raw_datafile_list {
	set firstword [lindex [split $line] 0]
	# Need to use glob to match comment characters
	switch -glob $firstword {
	    *data* {
		incr starting_index
		break
	    }
	    default {
		incr starting_index
	    }
	}
    }
    # Now we're at the data block
    foreach line [lrange $raw_datafile_list $starting_index end] {
	if {[string length $line] == 0} {
	    continue
	}
	lappend datafile_list $line
    }
    dict set datafile_dict file_data $datafile_list
    lappend datafile_dict_list $datafile_dict
    close $fid
    return $datafile_dict_list
}

proc get_fit_annotations {filename} {
    # Return a dictionary of annoations for the fit parameters
    #
    # Arguments:
    #   filename -- File containing the fit output parameters
    set line_list [read_file $filename]

    # Slope parameter
    set m_param [format "%0.2f" [lindex $line_list 0]]

    # Offset parameter
    set b_param [format "%0.2f" [lindex $line_list 1]]

    set key slope
    dict set annotation_dict $key title "Slope = "
    dict set annotation_dict $key value $m_param
    dict set annotation_dict $key units "^oC / m{/Symbol W}"

    set key offset
    dict set annotation_dict $key title "Offset = "
    dict set annotation_dict $key value $b_param
    dict set annotation_dict $key units "^oC"

    return $annotation_dict
}

proc write_gnuplot_data {datafile_dict_list} {
    # Write a data file that can be plotted by gnuplot
    #
    # This is where you can do some workup on the data before it's plotted.
    #
    # Arguments:
    #   datafile_dict_list -- List of dictionaries extracted from input datafiles
    global params
    global invoked_directory
    set output_file_tail "gnuplot.csv"
    set output_file_path ${invoked_directory}/$output_file_tail
    try {
	set fid [open $output_file_path w]
    } trap {} {message optdict} {
	puts $message
	exit
    }

    # Assign names to each column (starting with 0) so we can process
    # the raw values into measurements inside a switch statement.
    set count 0
    foreach datafile_dict $datafile_dict_list {
	set dummy_dict [dict create]
	try {
	    set title [dict get $datafile_dict title]

	    # Create a dummy dictionary that will eventually be copied
	    # back into the datafile_dict.  We can't modify the
	    # original dictionary inside this loop.
	    dict set dummy_dict title $title
	    set output_file_name "[string map {{ } _} $title].csv"

	    # The datafile_dict will contain the name of the file
	    # gnuplot will use to plot data.  This will be the
	    # worked-up data from the input files.
	    dict set dummy_dict gnuplot_data_file $output_file_name

	    puts "Found title: $title --> $output_file_name"
	    # The file_data will be a list of entries on each line of
	    # the file.  We can get the number of points by looking at
	    # the size of this list.
	    set data [dict get $datafile_dict file_data]
	    dict set dummy_dict file_data $data
	    set points [llength $data]
	    puts "Found points: $points"
	} trap {} {message optdict} {
	    puts $message
	    puts "Did not find a title"
	    set title "Column $count"
	}
	lappend column_name_list $title
	lappend dummy_dict_list $dummy_dict
	incr count
    }

    # Replace the original dictionary list with the modified version
    set datafile_dict_list $dummy_dict_list

    foreach dataset_dict $datafile_dict_list {
	logtable::print_dictionary $dataset_dict
    }

    foreach datafile_dict $datafile_dict_list {
	try {
	    set data [dict get $datafile_dict file_data]
	    set title [dict get $datafile_dict title]
	    set gnuplot_data_file [dict get $datafile_dict gnuplot_data_file]
	    # set Iin_mA [lindex [lindex $data $point] 0]
	    # set Iout_mA [lindex [lindex $data $point] 1]

	} trap {} {message optdict} {
	    puts $message
	}
	set output_file_path ${invoked_directory}/$gnuplot_data_file

	try {
	    set fid [open $output_file_path w]
	} trap {} {message optdict} {
	    puts $message
	    exit
	}

	foreach point $data {
	    # Do your data workup in here
	    set point_list [split $point ","]

	    set time_s [lindex $point_list 0]
	    set voltage_V [lindex $point_list 1]
	    set current_A [lindex $point_list 2]

	    puts $fid "$time_s,$voltage_V,$current_A"
	}
	close $fid

    }

    return $datafile_dict_list
}

proc write_gnuplot_script {annotation_dict datafile_dict_list} {
    # Write a gnuplot script to plot data in datafile
    #
    # Arguments:
    #   annotation_dict -- Dictionary of things to write on the plot
    #   datafile_dict_list -- List of dictionaries extracted from datafiles
    global gnuplot_terminal
    global program_name
    global params
    global invoked_directory

    # Write the gnuplot script where this script was invoked.  That
    # way, the user can run gnuplot on the script later.
    set output_file ${invoked_directory}/${program_name}.gp
    try {
	set fp [open $output_file w]
    } trap {} {message optdict} {
	puts $message
	exit
    }

    set plot_width 1100
    set plot_height 600

    # Spacing between lines of label text
    set label_spacing 0.1
    set top_label_y 0.8
    set label_x 0.6
    puts $fp "reset"
    puts $fp "set terminal $gnuplot_terminal 1 size $plot_width,$plot_height"
    puts $fp "set datafile separator ','"

    puts $fp "set ytics"
    puts $fp "set key outside right"

    # Now plot data using the first y-axis

    # set path [lindex $file_path_list 0]
    set datafile_dict_list [write_gnuplot_data $datafile_dict_list]

    ############################# X axis #############################

    # Which column contains X data (first column is 1)?
    set x_axis_column 1

    puts $fp "set xrange \[*:*\]"
    puts $fp "set format x '%0.0s %c'"
    puts $fp "set logscale x"
    puts $fp "set grid mxtics xtics mytics ytics"

    # Configure time formatting
    # puts $fp "set timefmt '%S'"
    # set xdata time
    # puts $fp "set xtics format '%H:%M' time"

    ########################## First y axis ##########################

    # Which column contains y1 data (first column is 1)?
    set y1_axis_column 3

    puts $fp "set format y '%0.0s %c'"
    puts $fp "set yrange \[*:*\]"
    puts $fp "set logscale y"
    # puts $fp "set yrange \[3.5:4.5]"

    # Start plotting!
    set linetype 0
    set output_string "plot "

    foreach datafile_dict $datafile_dict_list {
	incr linetype
	while {[lsearch {3 4 5} $linetype] != -1} {
	    # Avoid these linetypes
	    incr linetype
	}
	set gnuplot_data_file [dict get $datafile_dict gnuplot_data_file]
	set title [dict get $datafile_dict title]
	append output_string "'$gnuplot_data_file' \\\n"
	append output_string "using $x_axis_column:$y1_axis_column \\\n"
	append output_string "with lines linetype $linetype linewidth 1 \\\n"
	append output_string "axes x1y1 \\\n"
	append output_string "title '$title' noenhanced, \\\n"
    }

    # foreach entry $column_list {
    # 	set column [lindex $entry 0]
    # 	set title [lindex $entry 1]
    # 	incr linetype
    # 	while {[lsearch {3 4 5} $linetype] != -1} {
    # 	    # Avoid these linetypes
    # 	    incr linetype
    # 	}
    # 	# Apply line continuations and newlines to make the script prettier
    # 	append output_string "'$gnuplot_data_file' \\\n"
    # 	append output_string "using $x_axis_column:$column \\\n"
    # 	append output_string "with lines linetype $linetype linewidth 1 \\\n"
    # 	append output_string "axes x1y1 \\\n"
    #
    # 	# Use noenhanced for title to prevent underscores from becoming subscripts
    # 	append output_string "title '$title' noenhanced, \\\n"
    # }

    ######################### Second y axis ##########################
    # set column_list [list]

    # Add the second y-axis plot if you want
    # lappend column_list [list 4 "Charge current"]

    # puts $fp "set format y2 '%0.0s %c'"
    # puts $fp "set y2range \[0:20\]"
    #
    # if [llength $column_list] {
    # 	foreach entry $column_list {
    # 	    set column [lindex $entry 0]
    # 	    set title [lindex $entry 1]
    # 	    incr linetype
    # 	    while {[lsearch {3 4 5} $linetype] != -1} {
    # 		# Avoid these linetypes
    # 		incr linetype
    # 	    }
    # 	    # Apply line continuations and newlines to make the script prettier
    # 	    append output_string "'$gnuplot_data_file' \\\n"
    # 	    append output_string "using 1:$column \\\n"
    # 	    append output_string "with lines linetype $linetype dashtype 2 linewidth 1 \\\n"
    # 	    append output_string "axes x1y2 \\\n"
    #
    # 	    # Use noenhanced for title to prevent underscores from becoming subscripts
    # 	    append output_string "title '$title' noenhanced, \\\n"
    #
    # 	}
    # }

    puts $fp [string trim $output_string ", \\ \n"]

    # Annotation x postion in graph (0 --> 1) coordinates
    set anno_x 0.5
    # Annotation y position in graph (0 --> 1) coordinates
    set anno_y 0.95
    # Spacing between annotation lines in graph (0 --> 1) coordinates
    set anno_incr 0.05

    # Apply annotations
    foreach key [dict keys $annotation_dict] {
	switch -glob $key {
	    "title" {
		set annotation "[dict get $annotation_dict $key title]"
		set annotation_command "set title '$annotation' font 'Arial,14'"
		if [dict exists $annotation_dict $key enhanced] {
		    if [dict get $annotation_dict $key enhanced] {
			append annotation_command " enhanced"
		    } else {
			append annotation_command " noenhanced"
		    }
		} else {
		    append annotation_command " enhanced"
		}
		puts $fp $annotation_command
		# Need to replot here because the data has already been plotted
		puts $fp "replot"
		continue
	    }
	    "xlabel" {
		set annotation "[dict get $annotation_dict $key title] "
		if {[dict get $annotation_dict $key units] ne ""} {
		    append annotation "([dict get $annotation_dict $key units])"
		}
		set annotation_command "set xlabel '$annotation' font 'Arial,14'"
		if [dict exists $annotation_dict $key enhanced] {
		    if [dict get $annotation_dict $key enhanced] {
			append annotation_command " enhanced"
		    } else {
			append annotation_command " noenhanced"
		    }
		} else {
		    append annotation_command " enhanced"
		}
		puts $fp $annotation_command
		# Need to replot here because the data has already been plotted
		puts $fp "replot"
		continue
	    }
	    "ylabel" {
		set annotation "[dict get $annotation_dict $key title] "
		append annotation "([dict get $annotation_dict $key units])"
		set annotation_command "set ylabel '$annotation' font 'Arial,14'"
		if [dict exists $annotation_dict $key enhanced] {
		    if [dict get $annotation_dict $key enhanced] {
			append annotation_command " enhanced"
		    } else {
			append annotation_command " noenhanced"
		    }
		} else {
		    append annotation_command " enhanced"
		}
		puts $fp $annotation_command
		# Need to replot here because the data has already been plotted
		puts $fp "replot"
		continue
	    }
	    "y2label" {
		set annotation "[dict get $annotation_dict $key title]"
		if {$annotation eq ""} {
		    continue
		}
		puts $fp "set ytics nomirror"
		puts $fp "set y2tics"
		set annotation "[dict get $annotation_dict $key title] "
		append annotation "([dict get $annotation_dict $key units])"
		set annotation_command "set y2label '$annotation' font 'Arial,14'"
		if [dict exists $annotation_dict $key enhanced] {
		    if [dict get $annotation_dict $key enhanced] {
			append annotation_command " enhanced"
		    } else {
			append annotation_command " noenhanced"
		    }
		} else {
		    append annotation_command " enhanced"
		}
		puts $fp $annotation_command
		# Need to replot here because the data has already been plotted
		puts $fp "replot"
		continue
	    }
	    "script" {
		set annotation "[dict get $annotation_dict $key title]"
		append annotation "[dict get $annotation_dict $key value]"
		append annotation "[dict get $annotation_dict $key units]"
		set annotation_command "set label '$annotation' at graph 0.01,0.03 font 'Courier New,8'"
		if [dict exists $annotation_dict $key enhanced] {
		    if [dict get $annotation_dict $key enhanced] {
			append annotation_command " enhanced"
		    } else {
			append annotation_command " noenhanced"
		    }
		} else {
		    append annotation_command " enhanced"
		}
		puts $fp $annotation_command
		continue
	    }
	    default {
		# All general-purpose annotations go here
		set annotation "[dict get $annotation_dict $key title]"
		if {$annotation eq ""} {
		    continue
		}
		set annotation "[dict get $annotation_dict $key title]"
		append annotation "[dict get $annotation_dict $key value]"
		append annotation "[dict get $annotation_dict $key units]"
		set annotation_command "set label '$annotation' at graph $anno_x,$anno_y font 'Arial,12'"
		if [dict exists $annotation_dict $key enhanced] {
		    if [dict get $annotation_dict $key enhanced] {
			append annotation_command " enhanced"
		    } else {
			append annotation_command " noenhanced"
		    }
		} else {
		    append annotation_command " enhanced"
		}
		puts $fp $annotation_command
		# Increment (decrement) the y postion for the next annotation
		set anno_y [expr $anno_y - $anno_incr]
		puts $fp "replot"
	    }
	}

    }
    puts $fp "replot"

    # Draw voltage reference lines
    set refnum 1
    set label_offset_x_graph 0.05
    set label_offset_y_volt 0.5
    while {[set params(vr$refnum)] ne ""} {
	set volt_reference_v [set params(vr$refnum)]
	set label "${volt_reference_v}V"
	puts $fp [join [jpl::y_reference_line first $volt_reference_v $label 0.02 3] "\n"]

	incr refnum
    }

    # Make a slope line
    # set slope_line_negative_offset_s 500
    # set slope_line_positive_offset_s 100
    # set firstpoint [list [expr $outputs::max_voltage_time_s - $slope_line_negative_offset_s] \
    # 			[expr $outputs::max_voltage_voltage_v - \
    # 			     double($params(s))/1000 * $slope_line_negative_offset_s]]
    # set secondpoint [list [expr $outputs::max_voltage_time_s + $slope_line_positive_offset_s] \
    # 			 [expr $outputs::max_voltage_voltage_v + \
    # 			      double($params(s))/1000 * $slope_line_positive_offset_s]]
    # set deltas [expr [lindex $secondpoint 0] - [lindex $firstpoint 0]]
    # set deltav [expr [lindex $secondpoint 1] - [lindex $firstpoint 1]]
    # set slope [format %0.5f [expr double($deltav)/$deltas]]
    # puts "Max voltage is $outputs::max_voltage_voltage_v"
    # puts "Max time is $outputs::max_voltage_time_s"
    # puts "Slope is $slope"
    # puts $fp "set arrow from [lindex $firstpoint 0],[lindex $firstpoint 1] to [lindex $secondpoint 0],[lindex $secondpoint 1] nohead dashtype 2"
    #
    # puts $fp "set label '[expr 1000 * $slope] mV/s' at $outputs::max_voltage_time_s,$outputs::max_voltage_voltage_v right offset graph -0.02,graph 0.02"
    puts $fp "replot"

    close $fp
    return $output_file
}

proc pause {{message "Hit Enter to continue ==> "}} {
    puts -nonewline $message
    flush stdout
    gets stdin
}

########################## Main entry point ##########################

foreach name $input_file_name_list {
    # Filenames might come in as relative paths.  We need to give those a full path
    lappend input_file_path_list ${invoked_directory}/$name
}

# Gives you a namespace for calculated outputs
namespace eval outputs {}

# Each datafile will get its own dictionary entry
set datafile_dict_list [list]
foreach datafile $input_file_path_list {
    # Populate each datafile's dictionary and append it to the list
    set datafile_dict_list [read_file $datafile $datafile_dict_list]
}

foreach datafile_dict $datafile_dict_list {
    logtable::print_dictionary $datafile_dict
}

# Title is a special key for the plot title
set key title
dict set annotation_dict $key title $params(t)
dict set annotation_dict $key value ""
dict set annotation_dict $key units ""
dict set annotation_dict $key enhanced false

set key script
dict set annotation_dict $key title "Plotted with "
dict set annotation_dict $key value "[file_name_with_context $thisfile]"
dict set annotation_dict $key units ""
# Enhanced strings allow things like substripts and superscripts
dict set annotation_dict $key enhanced false

set key xlabel
dict set annotation_dict $key title "Time"
dict set annotation_dict $key value ""
dict set annotation_dict $key units "s"

set key ylabel
dict set annotation_dict $key title "Output current"
dict set annotation_dict $key value ""
dict set annotation_dict $key units "A"

set key y2label
dict set annotation_dict $key title ""
dict set annotation_dict $key value ""
dict set annotation_dict $key units "V"
dict set annotation_dict $key enhanced true

set gnuplot_script [write_gnuplot_script $annotation_dict $datafile_dict_list]

switch -exact $tcl_platform(os) {
    "Windows NT" {
	exec {*}[list $gnuplot --persist $gnuplot_script]
    }
    "Linux" {
	exec $gnuplot --persist $gnuplot_script

	# Even though the plot will persist after gnuplot exits, Emacs
	# eshell on Linux will kill the plot window when the Tcl program
	# finishes.  So we need a pause statement.
	pause "\nHit <enter> to exit"
    }

}

