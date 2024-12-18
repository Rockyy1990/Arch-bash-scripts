#!/usr/bin/env tclsh

# List of packages to install
set packages {
    "git"
    "vim"
    "htop"
    "curl"
    "wget"
    "python"
    "nodejs"
    "npm"
}

# Function to install packages using pacman
proc install_packages {pkgList} {
    foreach pkg $pkgList {
        puts "Installing package: $pkg"
        set result [exec sudo pacman -S --noconfirm $pkg]
        if {[catch {exec sudo pacman -S --noconfirm $pkg} result]} {
            puts "Error installing $pkg: $result"
        } else {
            puts "Successfully installed $pkg"
        }
    }
}

# Main execution
puts "Starting post-install script..."
install_packages $packages
puts "Post-install script completed."