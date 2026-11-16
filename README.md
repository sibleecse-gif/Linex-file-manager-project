# Linux File Manager (lfm)

A lightweight, dependency\-free Bash CLI for common project file management tasks on Linux.

## Features

- Initialize a managed directory with configuration and logs
- List files with filters (type, depth, human\-readable sizes)
- Search files by name, glob pattern, or regular expression
- Generate size and extension reports
- Create compressed .tar.gz archives with exclude patterns
- Perform incremental backups using rsync (supports dry\-run mode)
- Safe Trash/Restore workflow using ~/.local/share/lfm/trash
- Detect and remove duplicate files using SHA256 hashes
- Maintain operation audit logs
- Optional scheduled backups using systemd timers

## Quick Start

### Installation

\# Install (creates /usr/local/bin/lfm)

sudo ./install.sh

### Show Help

lfm help

### Initialize a Managed Directory

lfm init /path/to/project

### List Files

lfm list /path/to/project \-\-type file \-\-max\-depth 2

### Find Files by Pattern

lfm find /path/to/project \-\-name "\*.py"

### Generate a Size Report

lfm report /path/to/project \-\-by size

### Create an Archive

lfm archive /path/to/project \\

  \-\-output /backups/project\-$(date \+%F).tar.gz \\

  \-\-exclude "\*.log"

### Backup Using rsync

lfm backup /path/to/project \-\-to /backups/project \-\-dry\-run

### Move a File to Trash

lfm trash /path/to/project some/large\_file.bin

### Restore a File from Trash

lfm restore /path/to/project some/large\_file.bin

### Deduplicate Files

\# Dry\-run by default

lfm dedupe /path/to/project \-\-apply

### View Logs

lfm log /path/to/project

## Configuration

Configuration files are loaded in the following order (first match wins):

1. PROJECT/.lfm/lfm.conf
2. $XDG\_CONFIG\_HOME/lfm/config
3. ~/.config/lfm/config

### Example Configuration

\# lfm.conf

[core]

trash\_dir = ~/.local/share/lfm/trash

log\_file = .lfm/lfm.log

[backup]

rsync\_flags = \-aHAX \-\-delete \-\-info=stats1,progress2

exclude = .git,.lfm,\*.tmp,\*.swp

## Systemd Integration (Optional)

\# Copy service and timer files

sudo cp systemd/lfm\-backup.service /etc/systemd/system/

sudo cp systemd/lfm\-backup.timer /etc/systemd/system/

\# Reload systemd configuration

sudo systemctl daemon\-reload

\# Enable and start timer

sudo systemctl enable \-\-now lfm\-backup.timer

## Uninstallation

sudo ./uninstall.sh

## Safety Notes

- Backups support dry\-run mode before making changes.
- Files are moved to Trash instead of being permanently deleted.
- Deduplication should be reviewed before applying changes.
- Always verify command flags when working with critical data.

---

**Note:** lfm is designed to be safe by default by emphasizing dry\-runs, logging, and Trash\-based file removal instead of direct deletion. Always review operations before applying changes to production or critical data.

