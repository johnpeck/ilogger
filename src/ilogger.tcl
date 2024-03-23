


package require tcladu


try {
    set rm [visa::open-default-rm]
} trap {} {message optdict} {
    puts "Error opening default resource manager"
    puts $message
    exit
}

# open device
set visaAddr "USB0::0x1AB1::0x09C4::DM3R233202380::INSTR"
if { [catch { set vi [visa::open $rm $visaAddr] } rc] } {
    puts "Error opening instrument ‘$visaAddr‘\n$rc"
    # ‘rm‘ handle is closed automatically by Tcl
    exit
}
# Set timeout
chan configure $vi -timeout 500

# modinfo is needed to show loaded package versions
proc modinfo {modname} {
    # Return loaded module details.
    set modver [package require $modname]
    set modlist [package ifneeded $modname $modver]
    set modpath [lindex $modlist end]
    return "Loaded $modname module version $modver from ${modpath}."
}

proc send_command {channel command} {
    puts $channel $command
    after 1
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

# Main entry point
puts "* [modinfo tclvisa]\n"

chan configure stdin -blocking 0 -buffering none

# Send command to instrument. New line character is added automatically by ‘puts‘.
puts $vi "*CLS"

# Send command to query device identity string
send_command $vi "*IDN?"

# Read device’s answer. Trailing new line character is removed by ‘gets‘.
set id [gets $vi]
# puts "Identity of ‘$visaAddr‘ is ‘$id‘"

# Open the datafile
set datafile "clogger.dat"
try {
    set fid [open $datafile w+]
} trap {} {message optdict} {
    puts $message
    exit
}

puts "Connected to $id"
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
