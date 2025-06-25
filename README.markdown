# ilogger: Logging currents with the ADUSM100 / ADU100 #

Demo software for the for the [tcladu](https://github.com/johnpeck/tcladu) project.

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [ilogger: Logging currents with the ADUSM100 / ADU100](#ilogger-logging-currents-with-the-adusm100--adu100)
  - [Installing on 64-bit Linux (ubuntu)](#installing-on-64-bit-linux-ubuntu)
    - [Add a udev rule for the ADU100](#add-a-udev-rule-for-the-adu100)
    - [Install git](#install-git)
    - [Clone ilogger](#clone-ilogger)
    - [Get a tcladu release](#get-a-tcladu-release)
    - [Install Tcllib](#install-tcllib)
    - [Clone Logtable](#clone-logtable)
    - [Install Tcl bindings to sqlite](#install-tcl-bindings-to-sqlite)

<!-- markdown-toc end -->

## Installing on 64-bit Linux (ubuntu) ##

### Add a udev rule for the ADU100 ###

The software needs access to the [ADU100](https://www.ontrak.net/adu100.htm) hardware.  The
[Udev](https://opensource.com/article/18/11/udev) rule shown below
enables access by all users.  I name this file `10-ontrak.rules` and place it in `/usr/lib/udev/rules.d/`.

```properties
# Rule for ADU100
#
# If you change this, use
# sudo udevadm control --reload-rules
# ...to load the new rule.

# Everyone can read and write to the device
SUBSYSTEM=="usb", ATTRS{idVendor}=="0a07", ATTRS{idProduct}=="0064", MODE="0666"

# Only the owner (root) can read and write to the device
# SUBSYSTEM=="usb", ATTRS{idVendor}=="0a07", ATTRS{idProduct}=="0064", MODE="0600"
```

You need to

1. Place this rule in `/usr/lib/udev/rules.d`
2. Reload the udev rules with `sudo udevadm control --reload-rules`
3. Plug cycle the ADU100 to cause a new udev trigger

### Install git ###

`sudo apt install git`

### Clone ilogger ###

`git clone https://github.com/johnpeck/ilogger.git`

### Get a tcladu release ###

[Tcladu](https://github.com/johnpeck/tcladu) provides the
Tcl-to-libusb interface for the ADU100.  Place this where Tcl can find
packages.  I like `.local/share/tcltk` on linux, which ilogger will
add to Tcl's `auto_path` list.

```bash
mkdir -p .local/share/tcltk
cd .local/share/tcltk
wget https://github.com/johnpeck/tcladu/releases/download/v1.1.3/tcladu-1.1.3-linux-x64.tar.gz
tar xzvf tcladu-1.1.3-linux-x64.tar.gz
```

### Install Tcllib ###

[Tcllib](https://www.tcl-lang.org/software/tcllib/) provides
[cmdline](https://core.tcl-lang.org/tcllib/doc/trunk/embedded/md/tcllib/files/modules/cmdline/cmdline.md).
I use cmdline to implement functions with named arguments.

### Clone Logtable ###

[Logtable](https://github.com/johnpeck/logtable) provides some
functions to help with formatting the console log.  I like cloning this into `.local/share/tcltk`.

```bash
mkdir -p .local/share/tcltk
cd .local/share/tcltk
git clone https://github.com/johnpeck/logtable.git
```

### Install Tcl bindings to sqlite ###

Ilogger uses (SQLite)[https://sqlite.org/] to store calibration data in between runs.

```bash
sudo apt install libsqlite3-tcl
```

### Test the installation ###

Test things by running `ilogger.tcl -h` from the `src/` directory:

```bash
$ ilogger/src: tclsh ilogger.tcl -h
Loaded tcladu version 1.1.3
  Action script is:
  load /usr/share/tcltk/tcladu1.1.3/tcladu.so
  source /usr/share/tcltk/tcladu1.1.3/tcladu.tcl
Loaded cmdline version 1.5
  Action script is:
  source /usr/share/tcltk/tcllib1.20/cmdline/cmdline.tcl
Loaded inifile version 0.3.1
  Action script is:
  source /usr/share/tcltk/tcllib1.20/inifile/ini.tcl
Loaded logtable version 1.6
  Action script is:
  source ~/.local/share/tcltk/logtable-1.6/logtable.tcl

ilogger -- Plot sense resistor currents from ADU100

usage: ilogger.tcl [options]
 -sn value            ADU100 serial number (Empty if only one) <>
 -g value             Analog measurement gain (0, 1, ..., 7) <0>
 -c                   Calibrate single range (specified by -g) and exit
 -ca                  Calibrate all ranges and exit
 -d                   Dry run and exit
 -v                   Make more verbose
 --                   Forcibly stop option processing
 -help                Print this message
 -?                   Print this message
```
