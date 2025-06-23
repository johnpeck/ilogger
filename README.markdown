# ilogger: Logging currents with the ADUSM100 / ADU100 #

Demo software for the for the [tcladu](https://github.com/johnpeck/tcladu) project.

## Installing on 64-bit Linux (ubuntu) ##

### Add a udev rule for the ADU100 ###

The software needs access to the [ADU100](https://www.ontrak.net/adu100.htm) hardware.  The
[Udev](https://opensource.com/article/18/11/udev) rule shown below
enables access by all users.  I name this file `10-ontrak.rules` and place it in `/usr/lib/udev/rules.d/`.

<pre>
# Rule for ADU100
#
# If you change this, use
# sudo udevadm control --reload-rules
# ...to load the new rule.

# Everyone can read and write to the device
SUBSYSTEM=="usb", ATTRS{idVendor}=="0a07", ATTRS{idProduct}=="0064", MODE="0666"

# Only the owner (root) can read and write to the device
# SUBSYSTEM=="usb", ATTRS{idVendor}=="0a07", ATTRS{idProduct}=="0064", MODE="0600"
</pre>
