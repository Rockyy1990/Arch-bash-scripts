#!/usr/bin/env bash

read -p " Install and config perl for arch/manjaro. Press any key to continue.."

sudo pacman -S perl

# More user-friendly way to install Perl modules
sudo pacman -S cpanminus

# cpan is the regular installer for perl modules
# cpan install Tk
# cpan install Gtk2
# cpan install Wx

cpanm Tk
cpanm Gtk2
cpanm Wx
cpanm Config::Tiny
cpanm Config::Simple
cpanm File::HomeDir
cpanm File::Find
cpanm local::lib
cpanm Module::Build

clear
echo "Perl is now installed and configured"

