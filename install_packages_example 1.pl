#!/usr/bin/perl
use strict;
use warnings;
use Tk;
use IPC::System::Simple qw(system);

# List of packages to choose from
my @packages = qw(
    vim
    git
    htop
    curl
    wget
    firefox
    gimp
);

# List of LibreOffice packages
my @libreoffice_packages = qw(
    libreoffice-fresh
    libreoffice-fresh-de
);

# Create main window
my $mw = MainWindow->new;
$mw->title("Package Installer");

# Create a hash to store the state of checkboxes
my %selected;

# Create checkboxes for each package
foreach my $package (@packages) {
    $selected{$package} = 0; # Initialize selection state
    $mw->Checkbutton(
        -text    => $package,
        -variable => \$selected{$package},
        -onvalue => 1,
        -offvalue => 0,
    )->pack(-anchor => 'w');
}

# Create a label for LibreOffice packages
$mw->Label(-text => "LibreOffice Packages:")->pack(-anchor => 'w');

# Create checkboxes for LibreOffice packages
foreach my $package (@libreoffice_packages) {
    $selected{$package} = 0; # Initialize selection state
    $mw->Checkbutton(
        -text    => $package,
        -variable => \$selected{$package},
        -onvalue => 1,
        -offvalue => 0,
    )->pack(-anchor => 'w');
}

# Install button
$mw->Button(
    -text    => "Install Selected Packages",
    -command => sub {
        my @to_install = grep { $selected{$_} } keys %selected;
        if (@to_install) {
            my $package_list = join(' ', @to_install);
            my $command = "sudo pacman -S --noconfirm $package_list";
            eval {
                system($command);
                $mw->messageBox(-message => "Installation complete!");
            };
            if ($@) {
                $mw->messageBox(-message => "Error during installation: $@");
            }
        } else {
            $mw->messageBox(-message => "No packages selected.");
        }
    }
)->pack(-padx => 10, -pady => 10);

# Exit button
$mw->Button(
    -text    => "Exit",
    -command => sub { exit; }
)->pack(-padx => 10, -pady => 10);

# Start the main loop
MainLoop;