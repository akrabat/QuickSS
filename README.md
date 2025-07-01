# QuickSS

A macOS command-line utility written in Swift that captures screenshots of the
currently active window. It supports command-line options to save screenshots as
PNG files to the Downloads directory with timestamped names, custom filenames,
or copy directly to the clipboard.

## Installation

### Download binary (recommended)

Download the latest binary from the [releases page](https://github.com/akrabat/quickss/releases).

### Compile from source

```bash
swiftc quickss.swift -o quickss
```

## Alfred Workflow

An Alfred Workflow is provided on the [releases page](https://github.com/akrabat/quickss/releases).

- Press `control+option+command+4` to take a screenshot of the active window and put onto the clipboard.
- Press `shift+control+option+command+4` to take a screenshot of the active window and save the file to the Downloads folder.
- Alternatively, use the `screenshot` keyword in Alfred.

## Usage

```bash
# Save to Downloads with timestamp
./quickss

# Copy to clipboard
./quickss --clipboard

# Save with custom filename
./quickss --file "custom.png"

# Keep original retina resolution
./quickss --no-resize

# Show help message
./quickss --help
```

### Examples

Capture the top window of active application after 3 seconds.

    $ sleep 3 ; ./quickss

Taking continuous shots of top window every 5 seconds

    $ while true; do ./quickss ; sleep 5 ; done


## Command line options

- `--file <filename>`: Specify custom filename or path for the screenshot
- `--clipboard`: Copy screenshot to clipboard instead of saving to file
- `--no-resize`: Keep original retina resolution (default is to resize for smaller files)
- `-h, --help`: Display help message and usage information

Note: `--clipboard` and `--file` options are mutually exclusive.


## How it works

We use CoreGraphics to identify the currently active window and capture it using
the built-in `screencapture` command. Screenshots are saved with timestamps like
"Screenshot 2024-01-01 at 12.34.56.png" by default.
